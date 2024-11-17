pub usingnamespace @cImport({
    @cDefine("_GNU_SOURCE", {});
    @cInclude("errno.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("sys/fcntl.h");
    @cInclude("sys/ptrace.h");
    @cInclude("sys/syscall.h");
    @cInclude("sys/wait.h");
    @cInclude("unistd.h");
});
