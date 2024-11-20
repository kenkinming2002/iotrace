const std = @import("std");
const sys = @import("sys.zig");
const Packet = @import("Packet.zig");

const Sample = struct { count: usize, timestamp: f64 };
const Samples = std.ArrayList(Sample);
const SamplesArray = std.EnumArray(Packet.Type, Samples);

fn samples_array_init(allocator: std.mem.Allocator) SamplesArray {
    var result: SamplesArray = undefined;

    var iter = result.iterator();
    while (iter.next()) |entry| {
        const samples = entry.value;
        samples.* = Samples.init(allocator);
    }

    return result;
}

fn samples_array_deinit(self: *SamplesArray) void {
    var iter = self.iterator();
    while (iter.next()) |entry| {
        const samples = entry.value;
        samples.deinit();
    }
}

pub fn report(log_file_path: []const u8, step: f64, width: f64) !void {
    const allocator = std.heap.c_allocator;

    var samples_array = samples_array_init(allocator);
    defer samples_array_deinit(&samples_array);

    var max_timestamp: f64 = 0;

    var log_file = try std.fs.cwd().openFile(log_file_path, .{});
    defer log_file.close();

    var packet: Packet = undefined;
    while (try log_file.readAll(std.mem.asBytes(&packet)) == @sizeOf(@TypeOf(packet))) {
        const sample = Sample{
            .count = packet.count,
            .timestamp = packet.timestamp_sec(),
        };
        try samples_array.getPtr(packet.type).append(sample);
        max_timestamp = @max(max_timestamp, sample.timestamp);
    }

    var gnuplot = try sys.spawnvp_stdin("gnuplot", &[_][*c]u8{ @constCast("gnuplot"), @constCast("--persist"), null });
    defer gnuplot.wait() catch {};
    defer gnuplot.stdin.close();

    {
        var iter = samples_array.iterator();
        while (iter.next()) |entry| {
            const title = @tagName(entry.key);
            const samples = entry.value;

            try gnuplot.stdin.writer().print("${s} << EOD\n", .{title});
            {
                var count: usize = 0;
                var i: usize = 0;
                var j: usize = 0;

                var timestamp: f64 = 0.0;
                while (timestamp <= max_timestamp + step) : (timestamp += step) {
                    while (j < samples.items.len and timestamp >= samples.items[j].timestamp) {
                        count += samples.items[j].count;
                        j += 1;
                    }

                    while (i < j and timestamp - width > samples.items[i].timestamp) {
                        count -= samples.items[i].count;
                        i += 1;
                    }

                    try gnuplot.stdin.writer().print("{d}\n", .{count});
                }
            }
            try gnuplot.stdin.writer().print("EOD\n", .{});
        }
    }

    {
        try gnuplot.stdin.writer().print("set xlabel \"Time(s)\"\n", .{});
        try gnuplot.stdin.writer().print("set ylabel \"Rate(byte/s)\"\n", .{});

        try gnuplot.stdin.writer().print("plot", .{});

        var sep: []const u8 = " ";
        var iter = samples_array.iterator();
        while (iter.next()) |entry| {
            const title = @tagName(entry.key);

            try gnuplot.stdin.writer().print("{s}", .{sep});
            try gnuplot.stdin.writer().print("${s} using ($0 * {}):($1 / {}) title \"{s}\" with lines", .{ title, step, width, title });
            sep = ", ";
        }
        try gnuplot.stdin.writer().print("\n", .{});
    }
}
