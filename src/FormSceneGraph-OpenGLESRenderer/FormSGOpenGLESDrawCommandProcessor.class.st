"
I am a draw command processor that internally uses OpenGL ES for drawing a scene graph.
"
Class {
	#name : #FormSGOpenGLESDrawCommandProcessor,
	#superclass : #FormSGGPUDrawCommandProcessor,
	#instVars : [
		'context',
		'gl',
		'vertexBuffer',
		'indexBuffer',
		'colorProgram',
		'activeProgram',
		'viewBoxScale',
		'viewBoxOffset',
		'viewportRectangle',
		'texturedProgram'
	],
	#pools : [
		'UFFIOpenGLConstants'
	],
	#category : #'FormSceneGraph-OpenGLESRenderer'
}

{ #category : #'instance creation' }
FormSGOpenGLESDrawCommandProcessor class >> for: aContext [
	^ self new initializeWithContext: aContext
]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> activateProgram: program [
	activeProgram == program ifTrue: [ ^ self ].
	
	gl useProgram: program validHandle.
	program
		uniform: #viewBoxTransform float: viewBoxScale x float: viewBoxScale y float: viewBoxOffset x float: viewBoxOffset y;
		uniform: #activeTexture int: 0.
	activeProgram := program.

]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> activateVertexLayout [
	| vertexSize |
	vertexSize := ("position" 2 + "color" 4 + "texcoord" 2)*4.
	
	context gl
		enableVertexAttribArray: 0;
		vertexAttribPointer_index: 0 size: 2 type: GL_FLOAT normalized: GL_FALSE stride: vertexSize pointer: (ExternalAddress fromAddress: 0);
		
		enableVertexAttribArray: 1;
		vertexAttribPointer_index: 1 size: 4 type: GL_FLOAT normalized: GL_FALSE stride: vertexSize pointer: (ExternalAddress fromAddress: 8);
		
		enableVertexAttribArray: 2;
		vertexAttribPointer_index: 2 size: 2 type: GL_FLOAT normalized: GL_FALSE stride: vertexSize pointer: (ExternalAddress fromAddress: 24)
]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> beginRenderPass: framebuffer clearColor: clearColor [
	framebuffer activate.
	^ self beginRenderPassWithExtent: framebuffer extent clearColor: clearColor
]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> beginRenderPassWithExtent: framebufferExtent clearColor: clearColor [
	viewportRectangle := 0@0 extent: framebufferExtent.
	viewBoxScale := (2.0 / framebufferExtent x) @ (-2.0 / framebufferExtent y).
	viewBoxOffset := -1.0 @ 1.0.

	gl
		viewport_x: 0 y: 0 width: framebufferExtent x height: framebufferExtent y;
		enable: GL_SCISSOR_TEST;
		scissor_x: 0 y: 0 width: framebufferExtent x height: framebufferExtent y;
				
		clearColor_red: clearColor red green: clearColor green blue: clearColor blue alpha: clearColor alpha;
		clear: GL_COLOR_BUFFER_BIT;

		enable: GL_BLEND;
		blendFuncSeparate_sfactorRGB: GL_SRC_ALPHA dfactorRGB: GL_ONE_MINUS_SRC_ALPHA sfactorAlpha: GL_ONE dfactorAlpha: GL_ONE
		
]

{ #category : #shaders }
FormSGOpenGLESDrawCommandProcessor >> colorFragmentShader [
	^ '
#version 100

varying highp vec4 fColor;

void main()
{ 
	gl_FragData[0] = fColor;
}

'
]

{ #category : #shaders }
FormSGOpenGLESDrawCommandProcessor >> colorVertexShader [
	^ '
#version 100
attribute highp vec2 vPosition;
attribute highp vec4 vColor;

varying highp vec4 fColor;

uniform highp vec4 viewBoxTransform;

void main()
{ 
	fColor = vColor;
	gl_Position = vec4(vPosition*viewBoxTransform.xy + viewBoxTransform.zw, 0.0, 1.0);
}

'
]

{ #category : #compiling }
FormSGOpenGLESDrawCommandProcessor >> compileShader: shaderSource type: shaderType [
	| shader |
	shader := UFFIOpenGLShaderHandle for: context.
	shader type: shaderType;
		generate;
		source: shaderSource withUnixLineEndings;
		compile.
	shader compileStatus ifFalse: [ 
		self error: shader infoLog
	].
	^ shader
]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> drawElements: command [
	gl drawElements_mode: GL_TRIANGLES count: command indexCount type: GL_UNSIGNED_SHORT indices: (ExternalAddress fromAddress: command firstIndex * 2).
]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> endRenderPass [
]

{ #category : #initialization }
FormSGOpenGLESDrawCommandProcessor >> initializeWithContext: aContext [
	context := aContext.
	gl := context gl.
	
	colorProgram := self programWithVertexShader: self colorVertexShader fragmentShader: self colorFragmentShader.
	texturedProgram := self programWithVertexShader: self texturedVertexShader fragmentShader: self texturedFragmentShader.
]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> noTexture [
	self activateProgram: colorProgram.
]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> processDrawCommandList: commandList [
	self
		uploadVertices: commandList vertices;
		uploadIndices: commandList indices;
		activateVertexLayout.
		
	commandList drawCommands do: [ :each |
		each accept: self
	].

]

{ #category : #compiling }
FormSGOpenGLESDrawCommandProcessor >> programWithVertexShader: vertexSource fragmentShader: fragmentSource [
	^ self programWithVertexShader: vertexSource fragmentShader: fragmentSource vertexBindings: {
		#vPosition -> 0.
		#vColor -> 1.
		#vTexcoord -> 2.
	}
]

{ #category : #compiling }
FormSGOpenGLESDrawCommandProcessor >> programWithVertexShader: vertexSource fragmentShader: fragmentSource vertexBindings: vertexBindings [
	| vertexShader fragmentShader program |
	context asCurrentDo: [
		vertexShader := self compileShader: vertexSource type: GL_VERTEX_SHADER.
		fragmentShader := self compileShader: fragmentSource type: GL_FRAGMENT_SHADER.
		
		program := (UFFIOpenGLProgramHandle for: context) generate.
		vertexBindings do: [ :binding |
			program bindAttribute: binding key asString location: binding value
		].

		program
			attach: vertexShader;
			attach: fragmentShader.
	
		program link.
		program linkStatus ifFalse: [ 
			self error: program infoLog
		].
		
		^ program
	].

]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> setFormTexture: command [
	| texture |
	texture := context textureObjectFromForm: command form.
	self activateProgram: texturedProgram.
	gl bindTexture_target: GL_TEXTURE_2D texture: texture handle
]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> setScissor: command [
	| viewClippedRectangle scissorMin scissorMax |
	viewClippedRectangle := command rectangle intersect: viewportRectangle ifNone: [
		gl scissor_x: 0 y: 0 width: 0 height: 0.
		^ self
	].

	scissorMin := viewportRectangle origin floor.
	scissorMax := viewportRectangle corner ceiling.
	gl scissor_x: scissorMin x y: scissorMin y width: scissorMax x - scissorMin x height: scissorMax y - scissorMin y.
]

{ #category : #shaders }
FormSGOpenGLESDrawCommandProcessor >> texturedFragmentShader [
	^ '
#version 100

uniform sampler2D activeTexture;

varying highp vec4 fColor;
varying highp vec2 fTexcoord;

void main()
{ 
	gl_FragData[0] = fColor * texture2D(activeTexture, fTexcoord).bgra;
}

'
]

{ #category : #shaders }
FormSGOpenGLESDrawCommandProcessor >> texturedVertexShader [
	^ '
#version 100
attribute highp vec2 vPosition;
attribute highp vec4 vColor;
attribute highp vec2 vTexcoord;

varying highp vec4 fColor;
varying highp vec2 fTexcoord;

uniform highp vec4 viewBoxTransform;

void main()
{ 
	fColor = vColor;
	fTexcoord = vTexcoord;
	gl_Position = vec4(vPosition*viewBoxTransform.xy + viewBoxTransform.zw, 0.0, 1.0);
}

'
]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> uploadIndices: indices [
	| encodedIndices destOffset |
	encodedIndices := ByteArray new: indices size*2.
	destOffset := 0.
	indices do: [ :each |
		encodedIndices uint16AtOffset: destOffset put: each.
		destOffset := destOffset + 2
	].

	indexBuffer ifNil: [
		indexBuffer := (UFFIOpenGLBufferHandle for: context) generate
	].

	indexBuffer forTarget: GL_ELEMENT_ARRAY_BUFFER setData: encodedIndices withUsage: GL_STREAM_DRAW.
]

{ #category : #'as yet unclassified' }
FormSGOpenGLESDrawCommandProcessor >> uploadVertices: vertices [
	| encodedVertices destOffset |
	encodedVertices := ByteArray new: vertices size*4.
	destOffset := 0.
	vertices do: [ :each |
		encodedVertices float32AtOffset: destOffset put: each.
		destOffset := destOffset + 4
	].

	vertexBuffer ifNil: [
		vertexBuffer := (UFFIOpenGLBufferHandle for: context) generate
	].

	vertexBuffer forTarget: GL_ARRAY_BUFFER setData: encodedVertices withUsage: GL_STREAM_DRAW.
]