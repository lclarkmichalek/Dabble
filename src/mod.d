private {
    import std.stdio;
    import std.file;
    import std.regex : match;
    import std.algorithm : equal;
    import std.array : split, join;
    import std.path;
    import std.datetime;
    import std.string : strip;
    
    import utils;
    import ini;
}

class Module {
public:
    string package_name;
    string filename;
    string mod_file;

    SysTime last_built;
    SysTime last_parsed; // Last time we parsed imports from the file
    SysTime last_modified;
    bool needs_parse = false;
    bool needs_rebuild = false;

    bool is_root = false;
    
    Module[] imported;
    Module[] imports;

    string[] external_imports;

    /* Takes the filename of the module (For identification purpouses only, the
       file will not be read from disk */
    this(string filename, string src_path, string root_dir) {
        this.last_built = Clock.currTime();
        this.last_built.stdTime(0); // set to 0 if never built
        this.last_parsed = Clock.currTime();
        this.last_parsed.stdTime(0); // set to 0 if never parsed
        
        this.filename = filename;
        this.last_modified = timeLastModified(this.filename);
        this.package_name = get_package_name(filename, src_path);
        this.mod_file = buildPath(root_dir, ".dabble", "modules", package_name);
    }

    string toString() {
        return this.package_name;
    }

    // Returns true if there is a cycle in the imports. Must be called on root
    // module
    bool cycle_in_imports() in {
        assert(this.imported.length == 0,
               "Module.cycle_in_imports was not called on root object");
    } body {
        bool cycleprime(Module current, Module[] checked) {
            checked ~= current;
            foreach(imported; current.imports) {
                foreach(chkd; checked) {
                    if (imported is chkd)
                        return true;
                }
                if (cycleprime(imported, checked))
                    return true;
            }
            return false;
        }
        return cycleprime(this, this.imported);
    }
    unittest {
        auto m1 = new Module("/tmp/test.d", "/");
        auto m2 = new Module("/tmp/test2.d", "/");
        m1.add_imports(m2);
        auto m3 = new Module("/tmp/test3.d", "/");
        m2.add_imports(m3);
        assert(!m1.cycle_in_imports(), "Module.cycle_in_imports failed #1");
        m3.add_imports(m2);
        assert(m1.cycle_in_imports(), "Module.cycle_in_imports failed #2");
    }
    
    /* Adds the module to the imports and then adds this to the modules
       imported, if not allready there. */
    void add_imports(Module mod) {
        this.imports ~= mod;
        if (!mod.has_imported(this)) {
            mod.add_imported(this);
        }
    }

    /* Complementary function to add_imports */
    void add_imported(Module mod) {
        this.imported ~= mod;
        if (!mod.has_imports(this)) {
            mod.add_imports(this);
        }
    }

    /* Adds the string to the external imports array */
    void add_external_imports(string modname) {
        this.external_imports ~= modname;
    }

    /* Returns true if mod in imports list */
    bool has_imports(Module mod) {
        foreach (other; this.imports)
            if (mod == other)
                return true;
        return false;
    }

    /* Returns true if mod in imported list */
    bool has_imported(Module mod) {
        foreach (other; this.imported)
            if (mod == other)
                return true;
        return false;
    }

    /* Adds the string to the external imports array */
    bool has_external_imports(string modname) {
        foreach (other; this.external_imports)
            if (modname == other)
                return true;
        return false;
    }

    Module[] all_imports() {
        auto all = this.imports.dup;
        foreach(mod; this.imports) {
            foreach(imp; mod.all_imports())
                if (!inside(all, imp))
                    all ~= imp;
        }
        return all;
    }
    
    bool requires_reparse() {
        return this.last_modified > this.last_parsed || this.needs_parse;
    }
    bool requires_rebuild() {
        return this.last_modified > this.last_built || this.needs_rebuild;
    }

    // If this module requires rebuild, then so do all the modules it depends on
    void propogate_rebuild() {
        if (!requires_rebuild())
            return;
        foreach(mod; imported) {
            mod.needs_rebuild = true;
            mod.propogate_rebuild();
        }
    }
    
    private {
        string import_regex = r"^\s*import\s+([\w_]+\.)*[\w_]+(\s*:\s*([\w_]+\s*,\s*)*[\w_]+)?\s*;$";
        string package_regex = r"([\w_]+\.)*[\w_]+";
    }
    void parse_imports(Module[string] modules) {
        auto file = File(this.filename, "r");
        foreach(cline; file.byLine()) {
            string line = strip(cast(string)cline.dup);
            if (match(line, this.import_regex)) {
                // Remove first 7 chars ("import ")
                line = line[7..$];
                auto m = match(line, this.package_regex);
                string pkg_name = m.hit();
                if (pkg_name in modules)
                    this.add_imports(modules[pkg_name]);
                else {
                    this.add_external_imports(pkg_name);
                }
            }
        }
        this.last_parsed = Clock.currTime();
    }
    unittest {
        auto test = new Module("/tmp/test.d", "/");
        auto foo_bar = new Module("/tmp/foo/bar.d", "/");
        auto mod_dict = ["test": test, "foo.bar": foo_bar];
        string input =
            "import foo.bar;
import test : func;
import external;
asd;
casds {};
";

        File f = File("/tmp/dabbletest", "w");
        f.write(input);
        f.close();
        f = File("/tmp/dabbletest", "r");
        
        auto testing = new Module("/tmp/main.d", "/");
        testing.parse_imports(f, mod_dict);

        assert(testing.has_imports(test) && testing.has_imports(foo_bar),
               "Module.parse_imports failed standard imports");
        assert(testing.has_external_imports("external"),
               "Module.parse_imports failed external imports");

        assert(test.has_imported(testing) && foo_bar.has_imported(testing),
               "Module.parse_imports did not reflect parsed relationships");
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
                        this.add_imports(modules[modname]);
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
                        this.add_imported(modules[modname]);
                    }
                }
            }
        }
    }

    void write_mod_file() {
        IniData data;
        data["build"]["last_built"] = this.last_built.toISOString();
        data["core"]["last_parsed"] = this.last_parsed.toISOString();
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
            auto mod = new Module(fn,
                                  get(config, "internal", "src_dir"),
                                  get(config, "internal", "root_dir"));
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