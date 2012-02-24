import std.path;
import std.file;
import std.stdio;

import utils : filter;
import mod;
import config;
import ini;

void main() {
    version(unittest) {
        return;
    }
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
    scope(exit) write_dabble_conf(config, root_dir);
    debug writeln("Project name: ", get(config, "core", "name"));

    string src_dir;
    if (get(config, "core", "src_dir") == "") {
        src_dir = find_src_dir(root_dir);
        set(config, "core", "src_dir", relativePath(src_dir, root_dir));
    } else
        src_dir = absolutePath(get(config, "core", "src_dir"), root_dir);
    debug writeln("Source: ", src_dir);
    
    auto df_iter = dirEntries(src_dir, SpanMode.depth);
    Module[string] modules;
    foreach(string fn; df_iter)
        if (extension(fn) == ".d") {
            auto mod = new Module(fn, src_dir, root_dir);
            if (mod.has_mod_file())
                mod.read_mod_file();
            modules[mod.package_name] = mod;
        }
    debug writeln("Modules: ", modules);

    // Load files into memory and parse imports
    parse_files(modules);
    
    Module[string] roots = find_roots(modules);
    debug writeln("Roots: ", roots);

    foreach(mod; modules.values)
        mod.write_mod_file();
}

string find_root_dir() {
    string find_root_prime(string checking) {
        if (checking == "/")
            return "";
        if (exists(buildPath(checking, ".dabble")) && isDir(buildPath(checking, ".dabble")))
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
        string src_path = buildPath(checking, "src");
        if (exists(src_path) && isDir(src_path))
            score += 10;
        else
            src_path = checking;
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
