enum COLORS : string {
    red = "0;31m",
    green = "0;32m",
}

string scolor(string input, string color) {
    return cast(char)(27) ~ "[" ~ color ~ input ~ cast(char)27 ~ "[m";
}