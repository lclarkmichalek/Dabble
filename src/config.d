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

string library_location(IniData config, Module mod) {
    return buildPath(config["internal"]["root_dir"], "lib", mod.package_name);
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
bool lib_exists(IniData data) {
    auto lib = buildPath(data["internal"]["root_dir"], "lib");
    return exists(lib) && isDir(lib);
}

void init_lib(IniData data) {
    auto lib = buildPath(data["internal"]["root_dir"], "lib");
    mkdir(lib);
    mkdir(buildPath(lib, "obj"));
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

IniData get_config() {
    string root_dir = find_root_dir();
    bool root_found = root_dir != "";

    if (!root_found) {
        root_dir = guess_root_dir();
        if (!dot_dabble_exists(root_dir)) {
            writeln("Creating new .dabble directory in ", root_dir);
            init_dot_dabble(root_dir);
        }
        if (!dabble_conf_exists(root_dir)) {
            writeln("Creating new .dabble.conf file in ", root_dir);
            init_dabble_conf(root_dir);
        }
    }
    IniData config = get_dabble_conf(root_dir);
    config["internal"]["root_dir"] = root_dir;
    
    string src_dir;
    if (get(config, "core", "src_dir") == "") {
        src_dir = find_src_dir(root_dir);
        set(config, "core", "src_dir", relativePath(src_dir, root_dir));
    } else
        src_dir = absolutePath(get(config, "core", "src_dir"), root_dir);
    config["internal"]["src_dir"] = src_dir;
    return config;
}

string find_root_dir() {
    string find_root_prime(string checking) {
        if (checking == "/")
            return "";
        if (exists(buildPath(checking, ".dabble")) &&
            isDir(buildPath(checking, ".dabble")) ||
            exists(buildPath(checking, ".dabble.conf")) &&
            isFile(buildPath(checking, ".dabble.conf")))
            return checking;
        else
            return find_root_prime(buildNormalizedPath(checking, ".."));
    }
    return absolutePath(find_root_prime(getcwd()));
}

string guess_root_dir() {
    int[string] grade_roots(string checking, int[string] grades) {
        if (checking == "/")
            return grades;

        int score = 0;
        // check for src dir
        string src_path = buildPath(checking, "src");
        if (exists(src_path) && isDir(src_path))
            score += 10;
        else {
            // Check for project dir (common to have src in there) 
            src_path = buildPath(checking, baseName(checking));
            if (exists(src_path) && isDir(src_path))
                score += 5;
            src_path = checking;
        }
        auto src_files = dirEntries(src_path, SpanMode.shallow);
        foreach(string filename; src_files) {
            if (extension(filename) == ".d")
                score++;
        }
        grades[checking] = score;
        return grade_roots(buildNormalizedPath(checking, ".."), grades);
    }
    auto max_grade = -1;
    auto max_name = "";
    foreach(name, grade; grade_roots(getcwd, ["": -1])) {
        if (grade > max_grade) {
            max_grade = grade;
            max_name = name;
        }
    }
    return absolutePath(max_name);
}


string find_src_dir(string root) {
    auto src = buildPath(root, "src");
    if (exists(src) && isDir(src))
        return src;
    else
        return root;
}
