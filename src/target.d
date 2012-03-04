private {
    import core.cpuid;
    
    import std.array;
    import std.path;
    import std.process;
    import std.stdio;
    import std.file;
    import std.string;
    
    import ini, mod, config, color, utils;
}

class Target {
    string[] object_files;
    string[] d_files;
    string output;
    Module[] modules;
    string name;

    MODULE_TYPE type;

    this(Module[] depends, string location, MODULE_TYPE type, string name = "") {
        this.output = location;
        this.modules = depends;
        foreach(dep; depends)
            this.object_files ~= object_file(dep);
        this.object_files = unique(this.object_files);
        if (name == "")
            this.name = baseName(this.output);
        else
            this.name = name;
        this.type = type;
    }
    
    string link_cmdline() {
        string[] args;
        if (type == MODULE_TYPE.executable) {
            args = ["gcc", "-Xlinker"];
            args ~= this.object_files;
            args ~= ["-o", this.output];
            args ~= ["-L/usr/lib", "-lphobos2", "-lpthread", "-lm", "-lrt"];
            
            args ~= get_user_link_flags();
        } else {
            // TODO: Suppress output if !verbose
            args = ["ar", "-r"];
            args ~= this.output;
            args ~= this.object_files;
        }
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
        if (exists(output)) {
            if (getbool(conf, "ui", "verbose"))
                writeln("Deleating old target");
            remove(output);
        }
        
        if (getbool(conf, "ui", "verbose")) {
            write("Linking ", relativePath(output, getcwd()), "...");
            stdout.flush();
        }
        
        debug writeln(link_cmdline());
        int ok = system(link_cmdline());
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
                          MODULE_TYPE.library,
                          target_name);
    } else
        targ = new Target(mods,
                          buildPath(conf["internal"]["root_dir"], "bin", target_name),
                          MODULE_TYPE.executable,
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
                targ = new Target(root.imports ~ root,
                                  binary_location(root),
                                  MODULE_TYPE.executable);
            else
                targ = new Target(root.imports ~ root,
                                  library_location(root),
                                  MODULE_TYPE.library);
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