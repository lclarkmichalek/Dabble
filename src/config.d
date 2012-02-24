import std.path;
import std.file;
import std.stdio;
import std.regex;
import std.array : split;
import std.string : strip;

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
        auto fh = File(filename, "w");
        foreach(section_name, section; data) {
            fh.writeln("[", section_name, "]");
            foreach(key, value; section) {
                fh.writeln(key, "=", value);
            }
        }
    }

    private {
        string ini_header = r"^\[[\w _\d]+\]$";
        string ini_value = r"^\w+\s*=\s*\w+";
    }
    void read_config(string filename="") {
        // YAIP
        if (filename == "") {
            filename = buildPath(root_path, ".dabble.conf");
        }
        auto fh = File(filename, "r");
        string current_section = "";
        foreach(line; fh.byLine()) {
            if (match(line, this.ini_header)) {
                current_section = cast(string)line[1..$-1].dup;
            }
            if (match(line, this.ini_value) && current_section != "") {
                auto parts = split(line, "=");
                assert(parts.length == 2, "split ini kv was not len 2");
                string key = cast(string)strip(parts[0]).dup;
                string value = cast(string)strip(parts[1]).dup;
                this.data[current_section][key] = value;
            }
        }
    }

    string get(string sec, string name, string def="") {
        if (sec !in this.data || name !in this.data[sec])
            return def;
        return this.data[sec][name];
    }

    void set(string sec, string name, string val) {
        this.data[sec][name] = val;
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
    conf.set("core", "name", baseName(root));
    conf.write_config();
}