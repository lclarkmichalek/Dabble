private {
    import std.array;
    import std.path;
    import std.process;
    import std.stdio;
    import std.file;
    import std.string;
    
    import ini, mod, config, color;
}

class Target {
    string[] object_files;
    string[] d_files;
    string output;
    Module[] modules;
    string name;

    string[] link_flags; // Shove -lib in here if we're a library

    this(Module[] depends, string location, string name = "") {
        this.output = location;
        this.modules = depends;
        foreach(dep; depends)
            this.object_files ~= object_file(dep);
        if (name == "")
            this.name = baseName(this.output);
        else
            this.name = name;
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
        return this.name;
    }
}

Target[] get_targs_from_section(Module[string] modules, string sec_name) {
    auto section = conf[sec_name];
    Target[] targs;
    foreach(target, glob; section) {
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

Target load_targ(Module[string] modules, string section_name)
in {
    assert(section_name in conf, "Section name was not in config");
} body {
    auto section = conf[section_name];
    string target_name = cast(string)section_name.dup;
    munch(target_name, "target.");
    if ("glob" !in section) {
        writelnc("Target " ~ target_name ~ " had no glob value", COLORS.red);
        return null;
    }
    Module[] mods;
    Module main = null;
    foreach(mod; modules.values)
        if (globMatch(mod.package_name, section["glob"])) {
            mods ~= mod;
            if (mod.type == MODULE_TYPE.executable)
                main = mod;
        }
    Target targ;
    if (main is null) {
        targ = new Target(mods,
                          buildPath(conf["internal"]["root_dir"], "lib",
                                    target_name ~ ".a"),
                          target_name);
        targ.link_flags ~= "-lib";
    } else
        targ = new Target(mods,
                          buildPath(conf["internal"]["root_dir"], "bin", target_name),
                          target_name);
    return targ;
}

Target[] get_targets(Module[string] modules) {
    string bt = conf["internal"]["build_type"];
    Target[] alltargs, targs;
    foreach(secname; conf.keys) {
        if (startsWith(secname, "target.")) {
            auto targ = load_targ(modules, secname);
            if (targ !is null)
                alltargs ~= targ;
        }
    }
    auto wanted = getlist(conf, "build." ~ bt, "targets", []);
    if (alltargs.length != 0) {
        debug writeln("Found targets: ", alltargs);
        if (wanted.length == 0)
            targs = alltargs;
        else
            foreach(want; wanted) {
                bool found = false;
                foreach(targ; alltargs)
                    if (targ.name == want) {
                        found = true;
                        targs ~= targ;
                    }
                if (!found)
                    writelnc("Could not find target " ~ want, COLORS.red);
            }
    } else {
        // Autodetect roots
        auto roots = find_roots(modules);
        debug writeln("Autodetecting targets, roots: ", roots);
        foreach(root; roots) {
            Target targ;
            if (root.type == MODULE_TYPE.executable)
                targ = new Target(root.imports ~ root, binary_location(root));
            else
                targ = new Target(root.imports ~ root, library_location(root));
            if (wanted.length) {
                foreach(want; wanted)
                    if (want == targ.name)
                        targs ~= targ;
            } else
                targs ~= targ;
        }
    }
    return targs;
}

Target[] need_rebuild(Target[] targs) {
    Target[] rebuild;
    foreach(targ; targs)
        if (targ.requires_rebuild())
            rebuild ~= targ;
    return rebuild;
}