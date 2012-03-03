A[] filter(alias pred, A)(A[] input) if (is(typeof(pred(input[0])) == bool)) {
    A[] output;
    foreach(a; input)
        if (pred(a))
            output ~= a;
    return output;
}

B[] map(alias f, A, B)(A[] input) if (is(typeof(f(input[0])) == B)) {
    B[] output;
    foreach(a; input)
        output ~= f(a);
    return output;
 }

bool inside(A)(A[] input, A test) {
    foreach(testable; input)
        if (test == testable)
            return true;
    return false;
}

A[] unique(A)(A[] input) {
    string[A] tmp;
    foreach(a; input)
        tmp[a] = "";
    return tmp.keys;
}