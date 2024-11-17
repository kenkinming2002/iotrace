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

    const resolution_nsec = resolution_sec * 1e9;

    samples_array_iter = samples_array.iterator();
    while (samples_array_iter.next()) |entry| {
        const title = @tagName(entry.key);
        const samples = entry.value;

        try gnuplot.stdin.writer().print("${s} << EOD\n", .{title});
        {
            var index: usize = undefined;
            var count: usize = 0;
            for (samples.items) |sample| {
                const new_index: usize = @intFromFloat(@round(@as(f64, @floatFromInt(sample.timestamp)) / resolution_nsec));

                if (count != 0 and index != new_index) {
                    const rate = @as(f64, @floatFromInt(count)) / resolution_sec;
                    const time = @as(f64, @floatFromInt(index)) * resolution_sec;
                    try gnuplot.stdin.writer().print("{d} {d}\n", .{ rate, time });

                    count = 0;
                }

                index = new_index;
                count += sample.count;
            }

            if (count != 0) {
                const rate = @as(f64, @floatFromInt(count)) / resolution_sec;
                const time = @as(f64, @floatFromInt(index)) * resolution_sec;
                try gnuplot.stdin.writer().print("{d} {d}\n", .{ rate, time });
            }
        }
        try gnuplot.stdin.writer().print("EOD\n", .{});
    }

    try gnuplot.stdin.writer().print("set xrange [0:*]\n", .{});
    try gnuplot.stdin.writer().print("set yrange [0:*]\n", .{});

    try gnuplot.stdin.writer().print("set xlabel \"Time(s)\"\n", .{});
    try gnuplot.stdin.writer().print("set ylabel \"Rate(byte/s)\"\n", .{});

    try gnuplot.stdin.writer().print("plot", .{});

    var sep: []const u8 = " ";
    samples_array_iter = samples_array.iterator();
    while (samples_array_iter.next()) |entry| {
        const title = @tagName(entry.key);

        try gnuplot.stdin.writer().print("{s}", .{sep});
        try gnuplot.stdin.writer().print("${s} using 2:1 title \"{s}\" with lines", .{ title, title });
        sep = ", ";
    }
    try gnuplot.stdin.writer().print("\n", .{});
}
