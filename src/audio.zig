const std = @import("std");

// JavaScript callbacks for playing sounds
extern "env" fn playJumpSound() void;
extern "env" fn playExplodeSound() void;
extern "env" fn playFailSound() void;

// Sound types
pub const SoundType = enum {
    Jump,
    Explode,
    Fail,
};

pub const AudioSystem = struct {
    // Simple init method to register sounds if needed
    pub fn init() AudioSystem {
        return AudioSystem{};
    }

    // Play a sound by type
    pub fn playSound(self: *AudioSystem, sound_type: SoundType) void {
        _ = self; // Unused for now

        switch (sound_type) {
            .Jump => playJumpSound(),
            .Explode => playExplodeSound(),
            .Fail => playFailSound(),
        }
    }
};
