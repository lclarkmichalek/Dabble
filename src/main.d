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

    if (!bin_exists(config)) {
        init_bin(config);
    }
    if (!pkg_exists(config)) {
        init_pkg(config);
    }
    if (!lib_exists(config)) {
        init_lib(config);
    }

    auto modules = find_modules(config);
    Module[] reparsing;
    foreach(name, mod; modules) {
        if (mod.has_mod_file())
            mod.read_mod_file(modules);
        if (mod.requires_reparse())
            reparsing ~= mod;
    }
    if (reparsing.length != 0) {
        writeln("Parsing ", reparsing.length, " modules");
        bool fail = false;
        foreach(mod; reparsing)
            if(!mod.parse(modules)) {
                fail = true;
                break;
            }
        if (fail) {
            writelnc("Parsing failed", COLORS.red);
            return 1;
        } else
            writelnc("Done", COLORS.green);
    }
    scope(exit) foreach(mod; modules.values) mod.write_mod_file();
    
    Module[string] roots = find_roots(modules);
    foreach(root; roots.values) {
        if (root.type != MODULE_TYPE.executable)
            root.type = MODULE_TYPE.library;
    }

    Module[] recompiling;
    foreach(mod; modules.values) {
        if (mod.requires_rebuild()) {
            recompiling ~= mod ~ mod.imports;
        }
    }

    // This needs to be before the stuff is rebuild, else we cannot determin which modules
    // have been rebuilt
    Target[] targets = get_targets(config, modules);
    targets = need_rebuild(targets);

    if (recompiling.length != 0) {
        bool compiled;
        writeln("Compiling ", recompiling.length, " modules");
        bool built = compile(recompiling, config);
        if (!built) {
            writelnc("Compile failed", COLORS.red);
            return 1;
        } else {
            writelnc("Done", COLORS.green);
        }
    }

    if (targets.length != 0) {
        writeln("Linking ", targets.length, " targets");
        foreach(targ; targets) {
            if(!targ.link()) {
                writelnc("Link failed", COLORS.red);
                return 1;
            }
        }
        writelnc("Done", COLORS.green);
    }

    return 0;
}

bool compile(Module[] mods, IniData config) {
    auto pwd = getcwd();
    chdir(config["internal"]["src_dir"]);

    string[] arglist = ["dmd", "-c"];
    arglist ~= get_user_compile_flags(config);

    // All passed filenames need to be relative because -op is a bloody sham
    foreach(mod; unique(mods)) {
        bool cycle = false;
        arglist ~= relativePath(mod.filename, getcwd());
        
        // May not have been generated yet
        string obj = object_file(config, mod);
        if (!exists(dirName(obj)))
            mkdirRecurse(dirName(obj));
    }

    arglist ~= "-od" ~ buildPath(config["internal"]["root_dir"], "pkg",
                                 config["internal"]["build_type"]);
    arglist ~= "-op";
    
    debug writeln(join(arglist, " "));
    int compiled = system(join(arglist, " "));
    chdir(pwd);
    if (compiled == 0) {
        auto time = Clock.currTime();
        foreach(mod; mods)
            mod.last_built = time;
        return true;
    } else {
        return false;
    }
}