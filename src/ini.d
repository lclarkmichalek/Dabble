private {
    import std.path;
    import std.file;
    import std.stdio;
    import std.regex;
    import std.array : split;
    import std.string : strip;

    import utils;
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
    string ini_header = r"^\[\S+\]$";
    string ini_value = r"^\S+\s*=\s*\S+";
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

A getconv(alias conv, A)(IniData data, string sec, string name, A def_)
    if (is(typeof(conv(name)) == A))
{
    if (sec !in data || name !in data[sec])
        return def;
    return conv(data[sec][name]);
 }

string[] getlist(IniData data, string sec, string name, string[] def_) {
    auto raw = get(data, sec, name, "");
    if (raw == "")
        return def_;
    string[] output;
    foreach(ind; split(raw, ","))
        output ~= strip(ind);
    return output;
}

bool getbool(IniData data, string sec, string name, bool def=false) {
    if (sec !in data || name !in data[sec])
        return def;
    return data[sec][name] == "yes";
}

void set(ref IniData data, string sec, string name, string val) {
    data[sec][name] = val;
}