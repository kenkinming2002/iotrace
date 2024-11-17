const std = @import("std");
const sys = @import("sys.zig");
const Packet = @import("Packet.zig");

const Sample = struct { count: usize, timestamp: u64 };
const Samples = std.ArrayList(Sample);
const SamplesArray = std.EnumArray(Packet.Type, Samples);

pub fn report(log_file_path: []const u8, resolution_sec: f64) !void {
    const allocator = std.heap.c_allocator;

    var samples_array = SamplesArray.initUndefined();
    var samples_array_iter: SamplesArray.Iterator = undefined;

    samples_array_iter = samples_array.iterator();
    while (samples_array_iter.next()) |entry| {
        const samples = entry.value;
        samples.* = Samples.init(allocator);
    }

    defer {
        samples_array_iter = samples_array.iterator();
        while (samples_array_iter.next()) |entry| {
            const samples = entry.value;
            samples.deinit();
        }
    }

    var log_file = try std.fs.cwd().openFile(log_file_path, .{});
    defer log_file.close();

    var packet: Packet = undefined;
    while (try log_file.readAll(std.mem.asBytes(&packet)) == @sizeOf(@TypeOf(packet))) {
        try samples_array.getPtr(packet.type).append(.{ .count = packet.count, .timestamp = packet.timestamp });
    }

    var gnuplot = try sys.spawnvp_stdin("gnuplot", &[_][*c]u8{ @constCast("gnuplot"), @constCast("--persist"), null });
    defer gnuplot.wait() catch {};
    defer gnuplot.stdin.close();

    samples_array_iter = samples_array.iterator();
    while (samples_array_iter.next()) |entry| {
        const title = @tagName(entry.key);
        const samples = entry.value;

        try gnuplot.stdin.writer().print("${s} << EOD\n", .{title});
        for (samples.items) |sample| try gnuplot.stdin.writer().print("{d} {d}\n", .{ sample.count, sample.timestamp });
        try gnuplot.stdin.writer().print("EOD\n", .{});
    }

    try gnuplot.stdin.writer().print("set boxwidth {} absolute\n", .{resolution_sec});
    try gnuplot.stdin.writer().print("set style fill solid 1.0 noborder\n", .{});

    try gnuplot.stdin.writer().print("set xrange [0:*]\n", .{});
    try gnuplot.stdin.writer().print("set yrange [0:*]\n", .{});

    try gnuplot.stdin.writer().print("set xlabel \"time(s)\"\n", .{});
    try gnuplot.stdin.writer().print("set ylabel \"transfer(bytes)\"\n", .{});

    try gnuplot.stdin.writer().print("plot", .{});

    var sep: []const u8 = " ";
    samples_array_iter = samples_array.iterator();
    while (samples_array_iter.next()) |entry| {
        const title = @tagName(entry.key);

        try gnuplot.stdin.writer().print("{s}", .{sep});
        try gnuplot.stdin.writer().print("${s} using (round($2/1e9/{})*{}):1 smooth frequency with boxes title \"{s}\"", .{ title, resolution_sec, resolution_sec, title });
        sep = ", ";
    }
    try gnuplot.stdin.writer().print("\n", .{});
}
