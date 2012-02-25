private {
    import std.path;
    import std.file;
    import std.stdio;
    import std.regex;
    import std.array : split;
    import std.string : strip;
}
alias string[string][string] IniData;

void write_ini(IniData data, string filename) {
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
    string ini_value = r"^[\w_.]+\s*=\s*[.\w_/\\+-]+";
}

IniData read_ini(string filename) {
    // YAIP
    IniData data;
    auto fh = File(filename, "r");
    string current_section = "";
    foreach(line; fh.byLine()) {
        if (match(line, ini_header)) {
            current_section = cast(string)line[1..$-1].dup;
        }
        if (match(line, ini_value) && current_section != "") {
            auto parts = split(line, "=");
            assert(parts.length == 2, "split ini kv was not len 2");
            string key = cast(string)strip(parts[0]).dup;
            string value = cast(string)strip(parts[1]).dup;
            data[current_section][key] = value;
        }
    }
    return data;
}

string get(IniData data, string sec, string name, string def="") {
    if (sec !in data || name !in data[sec])
        return def;
    return data[sec][name];
}

void set(ref IniData data, string sec, string name, string val) {
    data[sec][name] = val;
}

