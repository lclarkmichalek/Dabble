private {
    import std.datetime;
    import std.path;
    import std.file;
    import std.stdio;
    import std.array : join;
    import std.process;
    
    import utils;
    import mod;
    import config;
    import ini;
}

int main() {
    version(unittest) {
        return;
    }
    string root_dir = find_root_dir();
    bool root_found = root_dir != "";

    if (!root_found) {
        root_dir = guess_root_dir();
        if (!dot_dabble_exists(root_dir)) {
            writeln("Creating new .dabble directory in ", root_dir);
            init_dot_dabble(root_dir);
        }
        if (!dabble_conf_exists(root_dir)) {
            writeln("Creating new .dabble.conf file in ", root_dir);
            init_dabble_conf(root_dir);
        }
    }
    IniData config = get_dabble_conf(root_dir);
    scope(exit) write_dabble_conf(config, root_dir);
    debug writeln("Project name: ", get(config, "core", "name"));

    string src_dir;
    if (get(config, "core", "src_dir") == "") {
        src_dir = find_src_dir(root_dir);
        set(config, "core", "src_dir", relativePath(src_dir, root_dir));
    } else
        src_dir = absolutePath(get(config, "core", "src_dir"), root_dir);

    auto modules = find_modules(src_dir, root_dir);

    bool dirty = false;
    foreach(name, mod; modules) {
        if (mod.has_mod_file())
            mod.read_mod_file(modules);
        if (mod.requires_reparse()) {
            writeln(mod.package_name, " changed, parsing imports");
            mod.parse_imports(modules);
            dirty = true;
        }
    }
    scope(exit) foreach(mod; modules.values) mod.write_mod_file();
    
    Module[string] roots = find_roots(modules);
    foreach(root; roots.values) {
        root.is_root = true;
        if (root.cycle_in_imports()) {
            writeln("Cycle detected in dependencies");
            return 1;
        }
    }
    debug writeln("Roots: ", roots);

    foreach(mod; modules.values) {
        if (mod.requires_rebuild()) {
            mod.propogate_rebuild();
        }
    }
    debug foreach(mod; modules.values) {
        if (mod.requires_rebuild())
            writeln(mod, " needs rebuild");
    }

    if (!bin_exists(root_dir)) {
        writeln("Creating bin directory");
        init_bin(root_dir);
    }
    if (!pkg_exists(root_dir)) {
        writeln("Creating pkg directory");
        init_pkg(root_dir);
    }

    Module[] buildables;
    foreach(mod; modules.values) {
        bool all_imports_buildable = true;
        foreach(imported; mod.imports) {
            if (imported.requires_rebuild())
                all_imports_buildable = false;
        }
        if (all_imports_buildable)
            buildables ~= mod;
    }

    // Don't use foreach as buildables will be changing length
    for (int i=0; buildables.length != i; i++) {
        auto mod = buildables[i];
        if (mod.requires_rebuild()) {
            bool built = build(mod, root_dir, modules);
            if (!built) {
                writeln("Failed to build ", mod.package_name);
                return 1;
            }

            foreach(mod_; modules.values) {
                // Continue if they're allready buildable
                if (inside(buildables, mod_))
                    continue;
                
                // Add any modules that has all buildable dependencies
                bool non_buildable_depend = false;
                foreach(depend; mod_.imports)
                    if (!inside(buildables, depend))
                        non_buildable_depend = true;
                if (!non_buildable_depend)
                    buildables ~= mod_;
            }
        }
    }
    
    return 0;
}

bool build(Module mod, string root_dir, Module[string] modules) {
    writeln("Building ", mod.package_name);
    string[] arglist = ["dmd", "-inline", "-c"];
    arglist ~= mod.filename;
    foreach(imported; unique(mod.all_imports()))  {
        arglist ~= imported.filename;
        arglist ~= object_file(root_dir, imported);
    }
    // Object file
    arglist ~= "-od" ~ object_dir(root_dir);

    writeln(join(arglist, " "));
    int compiled = system(join(arglist, " "));
    if (compiled != 0)
        return false;

    if (mod.is_root) {
        auto ok = link(mod, root_dir);
        if (!ok)
            return false;
    }
    mod.last_built = Clock.currTime();
    return true;
}

bool link(Module mod, string root_dir) {
    writeln("Linking ", mod.package_name);
    string[] arglist = ["dmd", "-inline"];
    foreach(imported; unique(mod.all_imports()~mod)) {
        arglist ~= object_file(root_dir, imported);
    }
    arglist ~= "-of" ~ binary_location(root_dir, mod);
    writeln(join(arglist, " "));
    int ok = system(join(arglist, " "));
    return ok == 0;
}

Module[string] find_modules(string src_dir, string root_dir) {
    auto df_iter = dirEntries(src_dir, SpanMode.depth);
    Module[string] modules;
    foreach(string fn; df_iter)
        if (extension(fn) == ".d") {
            auto mod = new Module(fn, src_dir, root_dir);
            modules[mod.package_name] = mod;
        }
    return modules;
}

string find_root_dir() {
    string find_root_prime(string checking) {
        if (checking == "/")
            return "";
        if (exists(buildPath(checking, ".dabble")) && isDir(buildPath(checking, ".dabble")))
            return checking;
        else
            return find_root_prime(buildNormalizedPath(checking, ".."));
    }
    return absolutePath(find_root_prime(getcwd()));
}

string guess_root_dir() {
    int[string] grade_roots(string checking, int[string] grades) {
        if (checking == "/")
            return grades;

        int score = 0;
        string src_path = buildPath(checking, "src");
        if (exists(src_path) && isDir(src_path))
            score += 10;
        else
            src_path = checking;
        auto src_files = dirEntries(src_path, SpanMode.shallow);
        foreach(string filename; src_files) {
            if (extension(filename) == ".d")
                score++;
        }
        grades[checking] = score;
        return grade_roots(buildNormalizedPath(checking, ".."), grades);
    }
    auto max_grade = -1;
    auto max_name = "";
    foreach(name, grade; grade_roots(getcwd, ["": -1])) {
        if (grade > max_grade) {
            max_grade = grade;
            max_name = name;
        }
    }
    return absolutePath(max_name);
}


string find_src_dir(string root) {
    auto src = buildPath(root, "src");
    if (exists(src) && isDir(src))
        return src;
    else
        return root;
}
