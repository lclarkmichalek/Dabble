private {
    import std.array;
    import std.path;
    import std.process;
    import std.stdio;
    import std.file;
    
    import ini, mod, config;
}

class Target {
    string[] object_files;
    string[] d_files;
    string output;
    IniData config;
    Module[] modules;

    string[] link_flags; // Shove -lib in here if we're a library

    this(IniData config, Module[] depends, string location) {
        this.config = config;
        this.output = location;
        this.modules = depends;
        foreach(dep; depends)
            this.object_files ~= object_file(config, dep);
    }
    
    string dmd_link_cmdline() {
        string[] args = ["dmd", "-c"];
        args ~= "-of" ~ this.output;
        args ~= get_user_link_flags(config);
        args ~= this.link_flags;
        args ~= this.object_files;
        return join(args, " ");
    }

    bool requires_rebuild() {
        if (!exists(output))
            return true;
        foreach(mod; modules)
            if (mod.requires_rebuild())
                return true;
        return false;
    }

    bool link() {
        write("Linking ", relativePath(output, getcwd()), "...");
        debug writeln(dmd_link_cmdline());
        int ok = system(dmd_link_cmdline());
        if (ok == 0)
            writeln("Ok");
        else
            writeln("Build failed");
        return ok == 0;
    }

    string toString() {
        return relativePath(this.output, getcwd());
    }
}

Target[] get_targets(IniData config, Module[string] modules) {
    string bt = config["internal"]["build_type"];
    Target[] targs;
    debug writeln(bt, " ", config.keys);
    if (bt ~ "_targets" in config) {
        string[string] globs = config[bt ~ "_targets"];
        foreach(glob, target; globs) {
            Module[] targ_mods;
            Module main;
            foreach(name, mod; modules)
                if (globMatch(name, glob)) {
                    if (mod.errored)
                        continue;
                    if (mod.type == MODULE_TYPE.executable)
                        // We're not checking for multiple executables, tut tut
                        main = mod;
                    targ_mods ~= mod;
                }

            Target targ;
            targ = new Target(config, targ_mods, target);
            if (main is null)
                targ.link_flags = ["-lib"];
            targs ~= targ;
        }
    } else {
        // Autodetect roots
        auto roots = find_roots(modules);
        foreach(root; roots) {
            Target targ;
            if (root.type == MODULE_TYPE.executable)
                targ = new Target(config, root.imports ~ root, binary_location(config, root));
            else
                targ = new Target(config, root.imports ~ root, library_location(config, root));
            targs ~= targ;
        }
    }
    debug writeln(targs);
    return targs;
}

Target[] need_rebuild(Target[] targs) {
    Target[] rebuild;
    foreach(targ; targs)
        if (targ.requires_rebuild())
            rebuild ~= targ;
    return rebuild;
}