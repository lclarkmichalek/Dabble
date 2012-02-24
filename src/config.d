import std.path;
import std.file;
import std.stdio;

class Config {
public:
    string[string][string] data;
    string root_path;

    this(string root) {
        this.root_path = root;
    }
    
    void write_config(string filename="") {
        if (filename == "") {
            filename = buildPath(root_path, ".dabble.conf");
        }
        auto fh = File(file, "w");
        foreach(section_name, section; data) {
            fh.writeln("[", section_name, "]");
            foreach(key, value; section) {
                fh.writeln(key, "=", value);
            }
        }
    }
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
    auto conf = new Config(root);
    conf.data["core"]["name"] = baseName(root);
    conf.write_config();
}
