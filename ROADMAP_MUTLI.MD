# WebAssembly Multithreading Roadmap for Zig Game Template

## Overview

This document outlines a strategy for implementing "zero-configuration" multithreading in our WebAssembly game template. The goal is to provide automatic performance benefits without requiring game developers to write explicit multithreaded code.

## Technical Foundation

### Web Workers and SharedArrayBuffer

Modern multithreading in WebAssembly relies on:

1. **Web Workers**: JavaScript's mechanism for running scripts in background threads
2. **SharedArrayBuffer**: Allows sharing memory between the main thread and workers
3. **Atomics**: Provides synchronization primitives for coordinating between threads

### Browser Support Considerations

- SharedArrayBuffer requires HTTPS and specific headers for security reasons:
  - `Cross-Origin-Opener-Policy: same-origin`
  - `Cross-Origin-Embedder-Policy: require-corp`
- Support is good in modern browsers (Chrome, Firefox, Safari, Edge)

## Implementation Strategy

### 1. Automatic Worker Pool

Create a system that:
- Automatically determines how many workers to spawn based on hardware concurrency
- Defaults to `navigator.hardwareConcurrency / 2` workers
- Provides a fallback to single-threaded operation when SharedArrayBuffer isn't supported

```javascript
// In webgl.js or a new workers.js file
function initWorkerPool() {
    const workerCount = Math.max(1, Math.floor((navigator.hardwareConcurrency || 2) / 2));
    const workers = [];
    
    if (typeof SharedArrayBuffer !== 'undefined') {
        for (let i = 0; i < workerCount; i++) {
            workers.push(new Worker('game-worker.js'));
        }
        return { workers, sharedMemory: new SharedArrayBuffer(MEMORY_SIZE) };
    } else {
        console.log("SharedArrayBuffer not supported - running in single-threaded mode");
        return null; // Fallback to single-threaded
    }
}
```

### 2. Task-Based Parallelism

Implement a task system that:
- Divides work into independent "tasks" that can be processed in parallel
- Automatically distributes tasks to available workers
- Handles synchronization and result collection

```zig
// In a new file: src/tasks.zig
pub const TaskType = enum {
    Physics,
    ParticleUpdate,
    AIProcessing,
    CollisionDetection,
};

pub const Task = struct {
    type: TaskType,
    data_offset: usize,
    data_size: usize,
    result_offset: usize,
};

pub const TaskSystem = struct {
    tasks: []Task,
    // Implementation details...
    
    pub fn scheduleTasks(self: *TaskSystem) void {
        // Signal JS to distribute tasks to workers
    }
    
    pub fn waitForCompletion(self: *TaskSystem) void {
        // Wait for all tasks to complete
    }
};
```

### 3. Parallelizable Game Subsystems

Identify game systems that can benefit from parallelization with minimal changes:

#### a. Particle Systems

```zig
// In entities.zig or a new particles.zig
pub const ParticleSystem = struct {
    // Particles can be updated independently
    particles: []Particle,
    
    pub fn updateParallel(self: *ParticleSystem, delta_time: f32) void {
        // Create update tasks for batches of particles
        const BATCH_SIZE = 1000;
        var task_count = (self.particles.len + BATCH_SIZE - 1) / BATCH_SIZE;
        
        // Schedule tasks and wait for completion
    }
};
```

#### b. Physics and Collision Detection

```zig
// In a new physics.zig file
pub fn updatePhysicsParallel(entities: []Entity, delta_time: f32) void {
    // Divide entities into batches for parallel processing
    // Note: Need careful handling for collision detection between batches
}
```

#### c. AI Processing

```zig
// In a new ai.zig file
pub fn updateAIParallel(ai_entities: []AIEntity, delta_time: f32) void {
    // Process AI logic in parallel when entities don't directly interact
}
```

### 4. Renderer Integration

The renderer can submit parallel tasks for processing while it waits for the previous frame to complete:

```zig
// In renderer.zig
pub fn beginFrame(self: *Renderer) void {
    // Start processing tasks while waiting for vsync/previous frame
    task_system.scheduleTasks();
    
    // Existing code...
    self.command_buffer.reset();
}

pub fn endFrame(self: *Renderer, img: Image) void {
    // Wait for task completion before rendering
    task_system.waitForCompletion();
    
    // Existing rendering code...
}
```

### 5. Automatic Thread Utilization

Make the system automatically scale based on the client's hardware:

```javascript
// In index.html, update the WASM imports
const imports = {
    env: {
        // Existing imports...
        
        // Add thread-related imports
        getHardwareConcurrency: () => navigator.hardwareConcurrency || 2,
        scheduleTasksOnWorkers: (tasks_ptr, task_count) => {
            if (!workerPool) return false;
            
            // Distribute tasks among workers
            // Return true if successful
            return true;
        }
    }
};
```

## Implementation Phases

### Phase 1: Worker Infrastructure
- Set up worker pool creation
- Implement SharedArrayBuffer memory sharing
- Create basic task distribution system
- Add fallback for browsers without SharedArrayBuffer

### Phase 2: Task Abstraction Layer
- Create the task definition system in Zig
- Implement task scheduling and synchronization
- Build the JS-side task distribution mechanism

### Phase 3: Parallelizable Subsystems
- Implement particle system parallelization
- Add physics batch processing
- Add optional AI parallel processing
- Add spatial partitioning for collision detection

### Phase 4: Developer Accessibility
- Create simple APIs that hide threading complexity
- Implement automatic performance scaling
- Add configuration options for advanced users

## Limitations and Considerations

1. **Data Dependencies**: Some game logic has tight dependencies and cannot be easily parallelized
2. **Synchronization Overhead**: For small games, thread synchronization might outweigh benefits
3. **Debug Complexity**: Multithreaded code is harder to debug
4. **Memory Usage**: Worker threads increase memory usage

## Developer Experience

The key goal is that developers using this template shouldn't need to understand multithreading. The API should be designed so that:

```zig
// Example of how a game developer would use the system
// They simply call these functions and the system handles threading
game.updateParticles(delta_time); // Automatically parallelized
physics.update(delta_time);       // Automatically parallelized
renderer.render();                // Waits for parallel tasks to complete
```

## Performance Monitoring

Include a simple performance monitoring system:

1. Measure time spent in different subsystems
2. Track benefits from parallelization
3. Allow disabling parallelization if it's not beneficial
4. Provide simple visualization of thread utilization

## Conclusion

This approach allows for "free" performance improvements without requiring developers to understand the complexities of multithreaded programming. By focusing on naturally parallelizable game subsystems and providing automatic thread scaling, we can offer meaningful speedups while maintaining the template's simplicity goal.
