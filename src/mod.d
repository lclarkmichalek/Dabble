private {
    import std.conv;
    import std.stdio;
    import std.file;
    import std.regex;
    import std.algorithm : equal;
    import std.array : split, join;
    import std.path;
    import std.datetime;
    import std.string : strip, splitLines;
    import std.process : shell, system;
    import std.exception : ErrnoException;
    
    import utils;
    import ini;
    import color;
    import config;
}

enum MODULE_TYPE {
    library, executable, module_
}

class Module {
public:
    string package_name;
    string filename;
    string rel_path;
    string mod_file;
    IniData config;

    SysTime last_built;
    SysTime last_parsed; // Last time we parsed imports from the file
    SysTime last_modified;
    bool needs_parse = false;
    bool needs_rebuild = false;
    bool errored = false;

    MODULE_TYPE type = MODULE_TYPE.module_;
    
    Module[] imported;
    Module[] imports;

    string[] external_imports;

    /* Takes the filename of the module (For identification purpouses only, the
       file will not be read from disk */
    this(string filename, IniData config) {
        this.config = config;
        this.last_built = Clock.currTime();
        this.last_built.stdTime(0); // set to 0 if never built
        this.last_parsed = Clock.currTime();
        this.last_parsed.stdTime(0); // set to 0 if never parsed
        
        this.filename = filename;
        this.rel_path = relativePath(this.filename, getcwd());
        this.last_modified = timeLastModified(this.filename);
        this.package_name = get_package_name(filename, get(config, "internal", "src_dir"));
        this.mod_file = buildNormalizedPath(get(config, "internal", "root_dir"),
                                            ".dabble", "modules",
                                            package_name ~ "." ~ config["internal"]["build_type"]);
    }

    string toString() {
        return this.rel_path;
    }

    // Returns true if there is a cycle in the imports. Must be called on root
    // module
    bool cycle_in_imports() {
        foreach(imports; this.imports)
            foreach(imported; this.imported)
                if (imports == imported)
                    return true;
        return false;
    }

    bool compile() {
        write("Compiling ", this.toString(), "...");
        string[] arglist = ["dmd", "-c"];
        arglist ~= get_user_compile_flags(config);
        
        arglist ~= this.filename;
        foreach(imports; this.imports) {
            bool cycle = false;
            arglist ~= imports.filename;

            // May not have been generated yet
            string obj = object_file(config, imports);
            if (exists(obj))
                arglist ~= obj;
        }

        arglist ~= "-od" ~ dirName(object_file(config, this));

        debug writeln(join(arglist, " "));
        int compiled = system(join(arglist, " "));
        if (compiled != 0) {
            writeln(scolor("Build failed", COLORS.red));
            this.errored = true;
            return false;
        } else {
            writeln(scolor("OK", COLORS.green));
            this.last_built = Clock.currTime();
            return true;
        }
    }

    bool requires_reparse() {
        return this.last_modified > this.last_parsed || this.needs_parse;
    }
    bool requires_rebuild() {
        return (this.last_modified > this.last_built || this.needs_rebuild) &&
            !this.errored;
    }

    // If this module requires rebuild, then so do all the modules it depends on
    void propogate_rebuild() {
        if (!requires_rebuild())
            return;
        foreach(mod; imported) {
            mod.needs_rebuild = true;
        }
    }
    
    
    private {
        //        version(Debug) {
        string import_regex = r"^import    (\w+\.)*\w+";
        string main_func_regex = r"^function\s+D main\s*$";
        /*        } else {
            enum import_regex = ctRegex!r"^import\s+([\w_]+\.)*[\w_]+\s*";
            enum main_func_regex = ctRegex!r"^function\s+D main\s*$";
            }*/
    }
    void parse_imports(Module[string] modules) {
        write("Parsing ", relativePath(this.filename, getcwd()), "...");
        string cmdline = "dmd -v -c -of/dev/null "~this.filename~" -I" ~
            get(config, "internal", "src_dir") ~ " 2>/dev/null";
        string output;
        try
            output = shell(cmdline);
        catch (ErrnoException) {
            this.errored = true;
            writeln(scolor("Parse failed", COLORS.red));
            return;
        }
        writeln(scolor("OK", COLORS.green));
        foreach(line; splitLines(output)) {
            line = strip(line);
            if (match(line, this.main_func_regex)) {
                this.type = MODULE_TYPE.executable;
            }
            auto m = match(line, this.import_regex);
            if (m) {
                // Remove first 7 chars ("import ")
                line = m.hit()[7..$];
                string pkg_name = strip(line);
                if (pkg_name in modules) {
                    auto mod = modules[pkg_name];
                    this.imports ~= mod;
                    mod.imported ~= this;
                } else {
                    this.external_imports ~= pkg_name;
                }
            }
        }
        this.last_parsed = Clock.currTime();
    }

    bool has_mod_file() {
        return exists(this.mod_file) && isFile(this.mod_file);
    }

    void read_mod_file(Module[string] modules) {
        IniData data = read_ini(this.mod_file);
        if (get(data, "build", "last_built") != "") {
            auto ftime = SysTime.fromISOString(get(data, "build", "last_built"));
            if (ftime > this.last_built)
                this.last_built = ftime;
        }
        if (get(data, "core", "last_parsed") != "") {
            auto ftime = SysTime.fromISOString(get(data, "core", "last_parsed"));
            if (ftime > this.last_parsed) {
                this.last_parsed = ftime;
                this.imports.length = 0;
                if ("imports" in data) {
                    auto import_names = data["imports"].keys;
                    foreach(modname; import_names) {
                        if (modname !in modules) {
                            this.needs_parse = true;
                            break;
                        }
                        auto mod = modules[modname];
                        this.imports ~= mod;
                        mod.imported ~= this;
                    }
                }
                this.imported.length = 0;
                if ("imported" in data) {
                    auto import_names = data["imported"].keys;
                    foreach(modname; import_names) {
                        if (modname !in modules) {
                            debug writeln(this.package_name, " ", modname);
                            this.needs_parse = true;
                            break;
                        }
                        auto mod = modules[modname];
                        this.imported ~= mod;
                        mod.imports ~= this;
                    }
                }
            }
        }
        if (get(data, "core", "type") != "") {
            this.type = to!MODULE_TYPE(get(data, "core", "type"));
        } else
            this.needs_parse = true;
    }

    void write_mod_file() {
        IniData data;
        data["build"]["last_built"] = this.last_built.toISOString();
        data["core"]["last_parsed"] = this.last_parsed.toISOString();
        data["core"]["type"] = to!string(this.type);
        foreach(mod; this.imports)
            data["imports"][mod.package_name] = mod.filename;
        foreach(mod; this.imported)
            data["imported"][mod.package_name] = mod.filename;
        write_ini(data, this.mod_file);
    }
}

pure Module[string] find_roots(Module[string] mods) {
    Module[string] roots;
    foreach(name, mod; mods) {
        if (mod.imported.length == 0)
            roots[name] = mod;
    }
    return roots;
}

Module[string] find_modules(IniData config) {
    auto df_iter = dirEntries(get(config, "internal", "src_dir"), SpanMode.depth);
    Module[string] modules;
    foreach(string fn; df_iter)
        if (extension(fn) == ".d") {
            auto mod = new Module(fn, config);
            modules[mod.package_name] = mod;
        }
    return modules;
}

Module[string] load_modules(IniData config) {
    auto mods = find_modules(config);
    foreach(name, mod; mods) {
        if (mod.has_mod_file())
            mod.read_mod_file(mods);
        if (mod.requires_reparse())
            mod.parse_imports(mods);
    }
    return mods;
}

string get_package_name(string file, string root_dir) {
    auto rel = relativePath(file, root_dir);
    rel = rel[0..$-2]; // Strip .d
    return join(split(rel, "/"), ".");
}
unittest {
    auto pkg = "/tmp/foo/test.d";
    assert(get_package_name(pkg, "/tmp") == "foo.test",
           "Filename.get_package_name failed #1");
    assert(get_package_name(pkg, "/") == "tmp.foo.test",
           "Filename.get_package_name failed #2");
}