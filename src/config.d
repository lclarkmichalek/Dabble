private {
    import std.path;
    import std.file;
    import std.stdio;
    
    import ini;
    import mod;
}

bool dot_dabble_exists(string root) {
    auto dabblef = buildPath(root, ".dabble");
    return exists(dabblef) && isDir(dabblef);
}

void init_dot_dabble(string root) {
    string dabblef = buildPath(root, ".dabble");
    mkdir(dabblef);
    mkdir(buildPath(dabblef, "modules"));
}

bool dabble_conf_exists(string root) {
    auto dabblef = buildPath(root, ".dabble.conf");
    return exists(dabblef) && isFile(dabblef);
}
void init_dabble_conf(string root) {
    IniData conf;
    conf["core"]["name"] = baseName(root);
    write_ini(conf, buildPath(root, ".dabble.conf"));
}

IniData get_dabble_conf(string root) {
    return read_ini(buildPath(root, ".dabble.conf"));
}

void write_dabble_conf(IniData data) {
    auto pth = buildPath(get(data, "internal", "root_dir"), ".dabble.conf");
    data.remove("internal");
    write_ini(data, pth);
}

bool bin_exists(IniData data) {
    auto bin = buildPath(data["internal"]["root_dir"], "bin");
    return exists(bin) && isDir(bin);
}

string binary_location(IniData config, Module mod) {
    string binname = mod.package_name;
    
    // Special case #1
    if ("targets" in config && binname in config["targets"])
        binname = get(config, "targets", binname);
    else if (binname == "main")
        binname = get(config, "core", "name", binname);
        
    return buildPath(config["internal"]["root_dir"], "bin", binname);
}

void init_bin(IniData data) {
    auto bin = buildPath(data["internal"]["root_dir"], "bin");
    mkdir(bin);
}

bool pkg_exists(IniData data) {
    auto pkg = buildPath(data["internal"]["root_dir"], "pkg");
    return exists(pkg) && isDir(pkg);
}

void init_pkg(IniData data) {
    auto pkg = buildPath(data["internal"]["root_dir"], "pkg");
    mkdir(pkg);
    mkdir(buildPath(pkg, "obj"));
}

string object_dir(IniData data) {
    return buildPath(data["internal"]["root_dir"], "pkg", "obj");
}

string object_file(IniData data, Module mod) {
    return buildPath(data["internal"]["root_dir"],
                     "pkg", "obj", mod.package_name ~ ".o");
}

string get_user_compile_flags(IniData data) {
    return get(data, "flags", "compile");
}

string get_user_link_flags(IniData data) {
    return get(data, "flags", "link");
}