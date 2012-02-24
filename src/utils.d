A[] filter(alias pred, A)(A[] input) if (is(typeof(pred(input[0])) == bool)) {
    A[] output;
    foreach(a; input)
        if (pred(a))
            output ~= a;
    return output;
}

B[] filter(alias f, A)(A[] input) if (is(typeof(f(input[0])) == B)) {
    B[] output;
    foreach(a; input)
        output ~= f(a);
    return output;
}