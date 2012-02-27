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

    writeln("Parsing modules");
    auto modules = load_modules(config);
    scope(exit) foreach(mod; modules.values) mod.write_mod_file();
    writeln("\nDone");
    
    Module[string] roots = find_roots(modules);
    foreach(root; roots.values) {
        if (root.type != MODULE_TYPE.executable)
            root.type = MODULE_TYPE.library;
    }

    foreach(mod; modules.values) {
        if (mod.requires_rebuild()) {
            mod.propogate_rebuild();
        }
    }

    // This needs to be before the stuff is rebuild, else we cannot determin which modules
    // have been rebuilt
    Target[] targets = get_targets(config, modules);
    targets = need_rebuild(targets);

    bool compiled;
    writeln("\nCompiling modules");
    // Compile all the roots to generate the .o files of all the modules
    foreach(mod; find_roots(modules)) {
        if (!mod.requires_rebuild())
            continue;
        
        compiled = true;
        bool built = mod.compile();
        if (!built) {
            mod.errored = true;
            continue;
        }
    }
    if (!getbool(config, "ui", "verbose")) {
        if (compiled) // i.e. did anything get printed
            writeln("\nDone");
        else
            writeln("Up to date");
    }

    writeln("\nLinking targets");
    
    foreach(targ; targets) {
        bool ok = targ.link();
    }
    if (targets.length != 0)
        writeln("\nDone");
    else
        writeln("Up to date\n");

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