import std.stdio;
import std.regex : match;
import std.algorithm : equal;
import std.array : split, join;
import std.path;

import utils : filter;

class Module {
public:
    string package_name;
    string filename;
    
    Module[] imported;
    Module[] imports;

    string[] external_imports;

    /* Takes the filename of the module (For identification purpouses only, the
       file will not be read from disk */
    this(string filename, string src_path) {
        this.filename = filename;
        this.package_name = get_package_name(filename, src_path);
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
                else
                    checked ~= imported;
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
    
    private {
        string import_regex = r"^\s*import\s+([\w_]+\.)*[\w_]+(\s*:\s*([\w_]+\s*,\s*)*[\w_]+)?\s*;$";
        string package_regex = r"([\w_]+\.)*[\w_]+";
    }
    void parse_imports(File file, Module[string] modules) {
        foreach(cline; file.byLine()) {
            string line = cast(string)cline.dup;
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
}

Module[string] find_roots(Module[string] mods) {
    Module[string] roots;
    foreach(name, mod; mods) {
        if (mod.imported.length == 0)
            roots[name] = mod;
    }
    return roots;
}

void parse_files(Module[string] mods) {
    foreach(mod; mods.byValue) {
        auto f = File(mod.filename, "r");
        mod.parse_imports(f, mods);
    }
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