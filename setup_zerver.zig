const std = @import("std");
const process = std.process;
const builtin = @import("builtin");

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const exe_name = if (builtin.os.tag == .windows) "http-zerver.exe" else "http-zerver";

    // Check if http-zerver already exists
    const check_cmd = if (builtin.os.tag == .windows) &[_][]const u8{
        "powershell",
        "-Command",
        "if (Test-Path ./" ++ exe_name ++ ") { exit 0 } else { exit 1 }",
    } else &[_][]const u8{
        "sh",
        "-c",
        "test -f ./" ++ exe_name,
    };

    const check_result = process.Child.run(.{
        .allocator = allocator,
        .argv = check_cmd,
    }) catch |err| {
        std.debug.print("Failed to check for existing file: {}\n", .{err});
        return err;
    };
    defer allocator.free(check_result.stdout);
    defer allocator.free(check_result.stderr);

    if (check_result.term.Exited == 0) {
        std.debug.print("http-zerver detected, skipping setup...\n", .{});
        return;
    }

    std.debug.print("Setting up http-zerver...\n", .{});

    // Cleanup any existing repo
    const cleanup_cmd = if (builtin.os.tag == .windows) &[_][]const u8{
        "powershell",
        "-Command",
        "if (Test-Path http-zerver-tmp) { Remove-Item -Recurse -Force http-zerver-tmp }",
    } else &[_][]const u8{
        "sh",
        "-c",
        "rm -rf http-zerver-tmp",
    };

    _ = try process.Child.run(.{
        .allocator = allocator,
        .argv = cleanup_cmd,
    });

    // Clone the repository
    std.debug.print("Cloning http-zerver repository...\n", .{});
    const clone_cmd = &[_][]const u8{
        "git",
        "clone",
        "https://github.com/haleth-embershield/http-zerver",
        "http-zerver-tmp",
    };

    const clone_result = try process.Child.run(.{
        .allocator = allocator,
        .argv = clone_cmd,
    });
    defer allocator.free(clone_result.stdout);
    defer allocator.free(clone_result.stderr);

    if (clone_result.term.Exited != 0) {
        std.debug.print("Failed to clone repository: {s}\n", .{clone_result.stderr});
        return error.GitCloneFailed;
    }

    // Build http-zerver
    std.debug.print("Building http-zerver...\n", .{});
    const build_cmd = if (builtin.os.tag == .windows) &[_][]const u8{
        "powershell",
        "-Command",
        "cd http-zerver-tmp; zig build; cd ..",
    } else &[_][]const u8{
        "sh",
        "-c",
        "cd http-zerver-tmp && zig build && cd ..",
    };

    const build_result = try process.Child.run(.{
        .allocator = allocator,
        .argv = build_cmd,
    });
    defer allocator.free(build_result.stdout);
    defer allocator.free(build_result.stderr);

    if (build_result.term.Exited != 0) {
        std.debug.print("Failed to build http-zerver: {s}\n", .{build_result.stderr});
        return error.BuildFailed;
    }

    // Copy the executable to root directory
    std.debug.print("Copying http-zerver executable to root directory...\n", .{});
    const copy_cmd = if (builtin.os.tag == .windows) &[_][]const u8{
        "powershell",
        "-Command",
        "Copy-Item http-zerver-tmp/zig-out/bin/" ++ exe_name ++ " ./" ++ exe_name,
    } else &[_][]const u8{
        "sh",
        "-c",
        "cp http-zerver-tmp/zig-out/bin/" ++ exe_name ++ " ./" ++ exe_name ++ " && chmod +x ./" ++ exe_name,
    };

    const copy_result = try process.Child.run(.{
        .allocator = allocator,
        .argv = copy_cmd,
    });
    defer allocator.free(copy_result.stdout);
    defer allocator.free(copy_result.stderr);

    if (copy_result.term.Exited != 0) {
        std.debug.print("Failed to copy executable: {s}\n", .{copy_result.stderr});
        return error.CopyFailed;
    }

    // Cleanup - remove the cloned repository
    std.debug.print("Cleaning up...\n", .{});
    const final_cleanup_cmd = if (builtin.os.tag == .windows) &[_][]const u8{
        "powershell",
        "-Command",
        "Remove-Item -Recurse -Force http-zerver-tmp",
    } else &[_][]const u8{
        "rm",
        "-rf",
        "http-zerver-tmp",
    };

    const final_cleanup_result = try process.Child.run(.{
        .allocator = allocator,
        .argv = final_cleanup_cmd,
    });
    defer allocator.free(final_cleanup_result.stdout);
    defer allocator.free(final_cleanup_result.stderr);

    std.debug.print("Setup complete! http-zerver has been copied to the root directory.\n", .{});
}
