module models.utils;

T annotateErr (T)(lazy T expr, lazy string msg, string file = __FILE__, size_t line = __LINE__) {
    try {
        return expr;
    } catch (Throwable e) {
        throw new Exception(msg, file, line, e);
    }
}
