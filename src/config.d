import std.path;
import std.file;
import std.stdio;

import ini;

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