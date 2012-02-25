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

    IniData config = get_config();
    scope(exit) write_dabble_conf(config);
    
    auto modules = load_modules(config);
    scope(exit) foreach(mod; modules.values) mod.write_mod_file();
    
    Module[string] roots = find_roots(modules);
    foreach(root; roots.values) {
        if (root.type != MODULE_TYPE.executable)
            root.type = MODULE_TYPE.library;
        if (root.cycle_in_imports()) {
            writeln("Cycle detected in dependencies");
            return 1;
        }
    }

    foreach(mod; modules.values) {
        if (mod.requires_rebuild()) {
            mod.propogate_rebuild();
        }
    }

    if (!bin_exists(config)) {
        writeln("Creating bin directory");
        init_bin(config);
    }
    if (!pkg_exists(config)) {
        writeln("Creating pkg directory");
        init_pkg(config);
    }
    if (!lib_exists(config)) {
        writeln("Creating lib directory");
        init_lib(config);
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
            bool built = build(mod, config);
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

bool build(Module mod, IniData config) {
    writeln("Building ", mod.package_name);
    string[] arglist = ["dmd", "-c"];
    arglist ~= get_user_compile_flags(config);
    arglist ~= mod.filename;
    foreach(imported; unique(mod.imports))  {
        arglist ~= imported.filename;
        arglist ~= object_file(config, imported);
    }
    // Object file
    arglist ~= "-od" ~ object_dir(config);

    debug writeln(join(arglist, " "));
    int compiled = system(join(arglist, " "));
    if (compiled != 0)
        return false;

    if (mod.type != MODULE_TYPE.module_) {
        auto ok = link(mod, config);
        if (!ok)
            return false;
    }
    mod.last_built = Clock.currTime();
    return true;
}

bool link(Module mod, IniData config) {
    writeln("Linking ", mod.package_name, " as a ", mod.type);
    string[] arglist = ["dmd"];
    arglist ~= get_user_link_flags(config);
    foreach(imported; unique(mod.imports ~mod)) {
        arglist ~= object_file(config, imported);
    }

    if (mod.type == MODULE_TYPE.library) {
        arglist ~= "-lib";
        arglist ~= "-of" ~ library_location(config, mod);
    } else {
        arglist ~= "-of" ~ binary_location(config, mod);
    }
    debug writeln(join(arglist, " "));
    int ok = system(join(arglist, " "));
    return ok == 0;
}
