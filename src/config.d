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

void write_dabble_conf(IniData data, string root) {
    write_ini(data, buildPath(root, ".dabble.conf"));
}

bool bin_exists(string root) {
    auto bin = buildPath(root, "bin");
    return exists(bin) && isDir(bin);
}

string binary_location(string root, Module mod) {
    return buildPath(root, "bin", mod.package_name);
}

void init_bin(string root) {
    auto bin = buildPath(root, "bin");
    mkdir(bin);
}

bool pkg_exists(string root) {
    auto pkg = buildPath(root, "pkg");
    return exists(pkg) && isDir(pkg);
}

void init_pkg(string root) {
    auto pkg = buildPath(root, "pkg");
    mkdir(pkg);
    mkdir(buildPath(pkg, "int"));
    mkdir(buildPath(pkg, "obj"));
}

string interface_file(string root, Module mod) {
    return buildPath(root, "pkg", "int", mod.package_name ~ ".di");
}

string object_dir(string root) {
    return buildPath(root, "pkg", "obj");
}

string object_file(string root, Module mod) {
    return buildPath(root, "pkg", "obj", mod.package_name ~ ".o");
}