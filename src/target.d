private {
    import std.array;
    import std.path;
    import std.process;
    import std.stdio;
    import std.file;
    
    import ini, mod, config, color;
}

class Target {
    string[] object_files;
    string[] d_files;
    string output;
    Module[] modules;

    string[] link_flags; // Shove -lib in here if we're a library

    this(Module[] depends, string location) {
        this.output = location;
        this.modules = depends;
        foreach(dep; depends)
            this.object_files ~= object_file(dep);
    }
    
    string dmd_link_cmdline() {
        string[] args = ["dmd", "-c"];
        args ~= "-of" ~ this.output;
        args ~= get_user_link_flags();
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
        if (getbool(conf, "ui", "verbose")) {
            write("Linking ", relativePath(output, getcwd()), "...");
            stdout.flush();
        }
        debug writeln(dmd_link_cmdline());
        int ok = system(dmd_link_cmdline());
        if (ok == 0) {
            if (getbool(conf, "ui", "verbose"))
                writelnc("Ok", COLORS.green);
        } else {
            if (getbool(conf, "ui", "verbose"))
                writelnc("Build failed", COLORS.red);
        }
        return ok == 0;
    }

    string toString() {
        return relativePath(this.output, getcwd());
    }
}

Target[] get_targs_from_section(Module[string] modules, string[string] section) {
    Target[] targs;
    foreach(glob, target; section) {
        Module[] targ_mods;
        Module main;
        foreach(name, mod; modules)
            if (globMatch(name, glob)) {
                if (mod.type == MODULE_TYPE.executable)
                    // We're not checking for multiple executables, tut tut
                    main = mod;
                targ_mods ~= mod;
            }
        
        string output;
        if (main is null)
            output = buildPath(conf["internal"]["root_dir"], "lib", target ~ ".a");
        else
            output = buildPath(conf["internal"]["root_dir"], "bin", target);
        Target targ;
        targ = new Target(targ_mods, output);
        if (main is null)
            targ.link_flags = ["-lib"];
        targs ~= targ;
    }
    return targs;
}

Target[] get_targets(Module[string] modules) {
    string bt = conf["internal"]["build_type"];
    Target[] targs;
    debug writeln(bt, " ", conf.keys);
    if (bt ~ "_targets" in conf)
        targs = get_targs_from_section(modules, conf[bt ~ "_targets"]);
    else if ("targets" in conf)
        targs = get_targs_from_section(modules, conf["targets"]);
    else {
        // Autodetect roots
        auto roots = find_roots(modules);
        foreach(root; roots) {
            Target targ;
            if (root.type == MODULE_TYPE.executable)
                targ = new Target(root.imports ~ root, binary_location(root));
            else
                targ = new Target(root.imports ~ root, library_location(root));
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