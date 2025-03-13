// Include audio data directly in the WASM module
const jump_audio = @embedFile("assets/audio/jump.ogg");
const explode_audio = @embedFile("assets/audio/explode.ogg");
const failure_audio = @embedFile("assets/audio/failure.ogg");

// JavaScript callback for playing sounds
extern "env" fn playAudioFromWasm(data_ptr: [*]const u8, data_len: usize, sound_id: u32) void;

// Sound types
pub const SoundType = enum(u32) {
    Jump = 0,
    Explode = 1,
    Fail = 2,
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
            .Jump => {
                playAudioFromWasm(jump_audio.ptr, jump_audio.len, @intFromEnum(sound_type));
            },
            .Explode => {
                playAudioFromWasm(explode_audio.ptr, explode_audio.len, @intFromEnum(sound_type));
            },
            .Fail => {
                playAudioFromWasm(failure_audio.ptr, failure_audio.len, @intFromEnum(sound_type));
            },
        }
    }
};
