// WebGL interface for ASCII Flappy Bird

// Global WebGL context and resources
let gl = null;
let texture = null;
let shaderProgram = null;
let vertexBuffer = null;

// Check if WebGL is supported by the browser
function isWebGLSupported() {
    try {
        const canvas = document.createElement('canvas');
        return !!(window.WebGLRenderingContext && 
            (canvas.getContext('webgl') || canvas.getContext('experimental-webgl')));
    } catch(e) {
        return false;
    }
}

// Initialize WebGL context and resources
function initWebGL(canvas) {
    try {
        // Initialize WebGL context
        gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
        if (!gl) {
            console.error('WebGL not supported');
            return false;
        }

        // Set up viewport
        gl.viewport(0, 0, canvas.width, canvas.height);
        gl.clearColor(0.0, 0.0, 0.0, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        // Create shader program
        const vertexShader = createShader(gl, gl.VERTEX_SHADER, `
            attribute vec2 aPosition;
            attribute vec2 aTexCoord;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = vec4(aPosition, 0.0, 1.0);
                vTexCoord = aTexCoord;
            }
        `);

        const fragmentShader = createShader(gl, gl.FRAGMENT_SHADER, `
            precision mediump float;
            varying vec2 vTexCoord;
            uniform sampler2D uTexture;
            void main() {
                gl_FragColor = texture2D(uTexture, vTexCoord);
            }
        `);

        shaderProgram = createProgram(gl, vertexShader, fragmentShader);
        gl.useProgram(shaderProgram);

        // Create vertex buffer for a fullscreen quad
        const positions = [
            -1.0, -1.0,
            1.0, -1.0,
            -1.0, 1.0,
            1.0, 1.0
        ];

        const texCoords = [
            0.0, 1.0,
            1.0, 1.0,
            0.0, 0.0,
            1.0, 0.0
        ];

        // Create and bind position buffer
        const positionBuffer = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(positions), gl.STATIC_DRAW);
        const positionLocation = gl.getAttribLocation(shaderProgram, 'aPosition');
        gl.enableVertexAttribArray(positionLocation);
        gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

        // Create and bind texture coordinate buffer
        const texCoordBuffer = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(texCoords), gl.STATIC_DRAW);
        const texCoordLocation = gl.getAttribLocation(shaderProgram, 'aTexCoord');
        gl.enableVertexAttribArray(texCoordLocation);
        gl.vertexAttribPointer(texCoordLocation, 2, gl.FLOAT, false, 0, 0);

        // Create texture
        texture = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

        // Create a 1x1 black texture as a placeholder
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, 1, 1, 0, gl.RGB, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0]));

        return true;
    } catch (e) {
        console.error('WebGL initialization error:', e);
        return false;
    }
}

// Helper function to create a shader
function createShader(gl, type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);

    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        console.error('Shader compilation error:', gl.getShaderInfoLog(shader));
        gl.deleteShader(shader);
        return null;
    }

    return shader;
}

// Helper function to create a shader program
function createProgram(gl, vertexShader, fragmentShader) {
    const program = gl.createProgram();
    gl.attachShader(program, vertexShader);
    gl.attachShader(program, fragmentShader);
    gl.linkProgram(program);

    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        console.error('Program linking error:', gl.getProgramInfoLog(program));
        return null;
    }

    return program;
}

// Render a frame with the given texture data
function renderFrame(textureData, width, height) {
    if (!gl || !texture) {
        console.error('WebGL not initialized');
        return false;
    }

    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, width, height, 0, gl.RGB, gl.UNSIGNED_BYTE, textureData);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

    return true;
}

// Execute batched WebGL commands
function executeBatchedCommands(commandBuffer, width, height, zigMemory) {
    if (!gl || !texture) {
        console.error('WebGL not initialized');
        return false;
    }
    
    // Parse command buffer from WASM memory
    const buffer = new Uint8Array(zigMemory.buffer);
    const commands = new Uint32Array(zigMemory.buffer, commandBuffer, 1);
    const numCommands = commands[0];
    
    // Command format: [opcode, param1, param2, ...] 
    const commandData = new Uint32Array(zigMemory.buffer, commandBuffer + 4, numCommands * 4);
    
    // Execute commands in batch
    for (let i = 0; i < numCommands; i++) {
        const cmdIndex = i * 4;
        const opcode = commandData[cmdIndex];
        
        switch(opcode) {
            case 1: // Texture upload (UploadTexture)
                const dataPtr = commandData[cmdIndex + 1];
                const frameData = new Uint8Array(zigMemory.buffer, dataPtr, width * height * 3);
                
                gl.bindTexture(gl.TEXTURE_2D, texture);
                gl.texImage2D(
                    gl.TEXTURE_2D, 0, gl.RGB, width, height, 0, 
                    gl.RGB, gl.UNSIGNED_BYTE, frameData
                );
                break;
                
            case 2: // Draw call (DrawArrays)
                gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
                break;
                
            default:
                console.error('Unknown WebGL command:', opcode);
                break;
        }
    }
    
    return true;
}

// Clear the canvas
function clearCanvas() {
    if (!gl) {
        console.error('WebGL not initialized');
        return;
    }

    gl.clear(gl.COLOR_BUFFER_BIT);
}

// Define WebGL constants for use in JavaScript
const GL_CONSTANTS = {
    GL_TEXTURE_2D: 0x0DE1,
    GL_RGB: 0x1907,
    GL_UNSIGNED_BYTE: 0x1401,
    GL_TRIANGLE_STRIP: 0x0005
};

// Export the WebGL interface
window.AsciiFlappyWebGL = {
    init: initWebGL,
    renderFrame: renderFrame,
    executeBatch: executeBatchedCommands,
    clearCanvas: clearCanvas,
    isSupported: isWebGLSupported,
    // Export WebGL constants
    GL_TEXTURE_2D: GL_CONSTANTS.GL_TEXTURE_2D,
    GL_RGB: GL_CONSTANTS.GL_RGB,
    GL_UNSIGNED_BYTE: GL_CONSTANTS.GL_UNSIGNED_BYTE,
    GL_TRIANGLE_STRIP: GL_CONSTANTS.GL_TRIANGLE_STRIP
}; 