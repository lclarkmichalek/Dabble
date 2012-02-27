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

    // Compile all the roots to generate the .o files of all the modules
    foreach(mod; find_roots(modules)) {
        if (!mod.requires_rebuild())
            continue;
        
        bool built = mod.compile();
        if (!built) {
            mod.errored = true;
            continue;
        }
    }

    Target[] targets = get_targets(config, modules);
    targets = need_rebuild(targets);
    
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