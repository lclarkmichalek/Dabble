private {
    import std.datetime;
    import std.path;
    import std.file;
    import std.stdio;
    import std.array : join;
    import std.process;
    import std.string;
    
    import utils;
    import mod;
    import config;
    import ini;
    import target;
    import color;
}

int main(string[] args) {
    version(unittest) {
        return;
    }
    
    IniData config = get_config();
    
    if (args.length > 1)
        config["internal"]["build_type"] = toLower(args[1]);
    else
        config["internal"]["build_type"] = "default";

    auto modules = load_modules(config);
    scope(exit) foreach(mod; modules.values) mod.write_mod_file();
    
    Module[string] roots = find_roots(modules);
    foreach(root; roots.values) {
        if (root.type != MODULE_TYPE.executable)
            root.type = MODULE_TYPE.library;
        if (root.cycle_in_imports()) {
            writeln(scolor("Cycle detected in dependencies", COLORS.red));
            return 1;
        }
    }

    foreach(mod; modules.values) {
        if (mod.requires_rebuild()) {
            mod.propogate_rebuild();
        }
    }
    
    Target[] targets = get_targets(config, modules);
    targets = need_rebuild(targets);

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
                mod.errored = true;
                continue;
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

    foreach(targ; targets) {
        bool ok = targ.link();
    }
    
    string[] couldnt_build;
    foreach(mod; modules.values) {
        if (mod.errored) {
            couldnt_build ~= relativePath(mod.filename, getcwd());
        }
    }

    if (couldnt_build.length != 0) {
        writeln(scolor("Couldn't build " ~ join(couldnt_build, ", "), COLORS.red));
    }
    
    return 0;
}

bool build(Module mod, IniData config) {
    write("Compiling ", relativePath(mod.filename, getcwd()), "...");
    string[] arglist = ["dmd", "-c"];
    arglist ~= get_user_compile_flags(config);
    arglist ~= mod.filename;
    foreach(imported; unique(mod.imports))  {
        arglist ~= imported.filename;
        arglist ~= object_file(config, imported);
    }
    // Object file
    arglist ~= "-od" ~ dirName(object_file(config, mod));

    debug writeln(join(arglist, " "));
    int compiled = system(join(arglist, " "));
    if (compiled != 0) {
        writeln(scolor("Build failed", COLORS.red));
        return false;
    }
    writeln(scolor("OK", COLORS.green));

    mod.last_built = Clock.currTime();
    return true;
}