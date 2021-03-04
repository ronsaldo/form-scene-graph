"
I am a context for an AGPU draw command processor. I am used for holding state that is common to different draw command processors.
"
Class {
	#name : #FormSGAGPUDrawCommandProcessorContext,
	#superclass : #Object,
	#instVars : [
		'device',
		'defaultRenderPass',
		'fontTextureAtlasCache',
		'shaderSignature',
		'vertexLayout',
		'colorPipelineState',
		'projectionInvertedY',
		'linearSampler',
		'linearSamplerBinding',
		'textureFromFormDictionary',
		'textureWithModificationCountDictionary',
		'renderTargetDictionary',
		'texturedPipelineState',
		'subpixelPipelineState',
		'hasTopLeftNdcOrigin',
		'linearGradientPipelineState',
		'radialGradientPipelineState',
		'premultipliedTexturedPipelineState',
		'fullyOpaqueTexturedPipelineState',
		'hasColorCorrection'
	],
	#classVars : [
		'DefaultHasColorCorrection'
	],
	#pools : [
		'AGPUConstants'
	],
	#category : #'FormSceneGraph-AbstractGPURenderer'
}

{ #category : #testing }
FormSGAGPUDrawCommandProcessorContext class >> agpuUISettingsOn: aBuilder [
	<systemsettings>
	(aBuilder setting: #hasColorCorrection)
		parent: #agpu;
		label: 'Enable sRGB color correction for the UI renderer.';
		description: 'This enables the usage of the linear sRGB color space for computations.';
		target: self

]

{ #category : #'instance creation' }
FormSGAGPUDrawCommandProcessorContext class >> for: device [
	^ self basicNew initializeWithDevice: device; yourself
]

{ #category : #'instance creation' }
FormSGAGPUDrawCommandProcessorContext class >> for: device withColorCorrection: colorCorrectionEnabled [
	^ self basicNew
		hasColorCorrection: colorCorrectionEnabled;
		initializeWithDevice: device;
		yourself
]

{ #category : #testing }
FormSGAGPUDrawCommandProcessorContext class >> hasColorCorrection [
	^ DefaultHasColorCorrection ifNil: [ DefaultHasColorCorrection := true ]
]

{ #category : #testing }
FormSGAGPUDrawCommandProcessorContext class >> hasColorCorrection: aBoolean [
	DefaultHasColorCorrection := aBoolean
]

{ #category : #initialization }
FormSGAGPUDrawCommandProcessorContext >> colorBufferFormat [
	^ self hasColorCorrection
		ifTrue: [ AGPU_TEXTURE_FORMAT_B8G8R8A8_UNORM_SRGB ]
		ifFalse: [ AGPU_TEXTURE_FORMAT_B8G8R8A8_UNORM ]
]

{ #category : #shaders }
FormSGAGPUDrawCommandProcessorContext >> colorFragmentShader [
	^ '
#version 450

layout(location=0) in vec4 inColor;
layout(location=0) out vec4 outColor;
	
void main()
{ 
	outColor = vec4(inColor.rgb*inColor.a, inColor.a);
}

'
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> colorGamma [
	^ self hasColorCorrection ifTrue: [ 2.2 ] ifFalse: [1.0]
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> colorPipelineState [

	^ colorPipelineState
]

{ #category : #initialization }
FormSGAGPUDrawCommandProcessorContext >> compileShader: shaderType source: shaderSource [
	| shaderCompiler sourceText |
	sourceText := shaderSource withUnixLineEndings utf8Encoded.
	shaderCompiler := device createOfflineShaderCompiler.
	^ [
		shaderCompiler
			setShaderSource: AGPU_SHADER_LANGUAGE_VGLSL stage: shaderType sourceText: sourceText	  sourceTextLength: sourceText size;
			compileShader: AGPU_SHADER_LANGUAGE_DEVICE_SHADER options: '';
			getResultAsShader
		] on: AGPUError do: [ :e |
			e errorCode = AGPU_COMPILATION_ERROR ifTrue: [ 
				| logLength logBuffer compilationError |
				logLength := shaderCompiler getCompilationLogLength.
				logBuffer := ExternalAddress allocate: logLength + 1.
				compilationError := [
					shaderCompiler getCompilationLog: logLength + 1 buffer: logBuffer.
					logBuffer readString.
				] ensure: [ logBuffer free ].
				self error: compilationError
			] ifFalse: [
				e signal
			]
		]
]

{ #category : #initialization }
FormSGAGPUDrawCommandProcessorContext >> createPipelineStateBuilder [
	^ device createPipelineBuilder
		setShaderSignature: shaderSignature;
		setVertexLayout: vertexLayout;
		setRenderTargetCount: 1;	
		setRenderTargetFormat: 0 format: self colorBufferFormat;
		setDepthStencilFormat: AGPU_TEXTURE_FORMAT_UNKNOWN;
		setPrimitiveType: AGPU_TRIANGLES;
		setBlendState: 1 enabled: 1;
		setBlendFunction: 1
			sourceFactor: AGPU_BLENDING_ONE destFactor: AGPU_BLENDING_INVERTED_SRC_ALPHA colorOperation: AGPU_BLENDING_OPERATION_ADD
			sourceAlphaFactor: AGPU_BLENDING_ONE destAlphaFactor: AGPU_BLENDING_INVERTED_SRC_ALPHA alphaOperation: AGPU_BLENDING_OPERATION_ADD;
		yourself
]

{ #category : #initialization }
FormSGAGPUDrawCommandProcessorContext >> createPipelineStates [
	| vertexShader |
	vertexShader := self compileShader: AGPU_VERTEX_SHADER source: self vertexShader.
	colorPipelineState := self createPipelineStateBuilder
		attachShader: vertexShader;
		attachShader: (self compileShader: AGPU_FRAGMENT_SHADER source: self colorFragmentShader);
		build.

	texturedPipelineState := self createPipelineStateBuilder
		attachShader: vertexShader;
		attachShader: (self compileShader: AGPU_FRAGMENT_SHADER source: self texturedFragmentShader);
		build.

	fullyOpaqueTexturedPipelineState := self createPipelineStateBuilder
		attachShader: vertexShader;
		attachShader: (self compileShader: AGPU_FRAGMENT_SHADER source: self fullyOpaqueTexturedFragmentShader);
		setBlendFunction: 1
			sourceFactor: AGPU_BLENDING_ONE destFactor: AGPU_BLENDING_ZERO colorOperation: AGPU_BLENDING_OPERATION_ADD
			sourceAlphaFactor: AGPU_BLENDING_ONE destAlphaFactor: AGPU_BLENDING_ZERO alphaOperation: AGPU_BLENDING_OPERATION_ADD;
		build.
		
	premultipliedTexturedPipelineState := self createPipelineStateBuilder
		attachShader: vertexShader;
		attachShader: (self compileShader: AGPU_FRAGMENT_SHADER source: self premultipliedTexturedFragmentShader);
		build.
		
	linearGradientPipelineState := self createPipelineStateBuilder
		attachShader: vertexShader;
		attachShader: (self compileShader: AGPU_FRAGMENT_SHADER source: self linearGradientFragmentShader);
		build.

	radialGradientPipelineState := self createPipelineStateBuilder
		attachShader: vertexShader;
		attachShader: (self compileShader: AGPU_FRAGMENT_SHADER source: self radialGradientFragmentShader);
		build.

	subpixelPipelineState := self createPipelineStateBuilder
		attachShader: vertexShader;
		attachShader: (self compileShader: AGPU_FRAGMENT_SHADER source: self subpixelFragmentShader);
		setBlendFunction: 1
			sourceFactor: AGPU_BLENDING_ONE destFactor: AGPU_BLENDING_INVERTED_SRC_1COLOR colorOperation: AGPU_BLENDING_OPERATION_ADD
			sourceAlphaFactor: AGPU_BLENDING_ONE destAlphaFactor: AGPU_BLENDING_INVERTED_SRC_ALPHA alphaOperation: AGPU_BLENDING_OPERATION_ADD;
		build.
		
]

{ #category : #initialization }
FormSGAGPUDrawCommandProcessorContext >> createRenderPassWithColor: color [
	| colorAttachment |
	^ [
		| renderpassDescription |
		colorAttachment := AGPURenderpassColorAttachmentDescription externalNew.
		colorAttachment
			format: self colorBufferFormat;
			begin_action: AGPU_ATTACHMENT_CLEAR;
			end_action: AGPU_ATTACHMENT_KEEP;
			clear_value: color asAGPUColor4f;
			sample_count: 1;
			sample_quality: 0.
		renderpassDescription := AGPURenderpassDescription new.
		renderpassDescription
			color_attachment_count: 1;
			color_attachments: colorAttachment.
		device createRenderPass: renderpassDescription.
	] ensure: [colorAttachment free].

]

{ #category : #initialization }
FormSGAGPUDrawCommandProcessorContext >> createSampler [
	linearSampler := device createSampler: (AGPUSamplerDescription new
		filter: AGPU_FILTER_MIN_LINEAR_MAG_LINEAR_MIPMAP_LINEAR;
		address_u: AGPU_TEXTURE_ADDRESS_MODE_WRAP;
		address_v: AGPU_TEXTURE_ADDRESS_MODE_WRAP;
		address_w: AGPU_TEXTURE_ADDRESS_MODE_WRAP;
		max_lod: 10000.0;
		yourself).
	linearSamplerBinding := shaderSignature createShaderResourceBinding: 0.
	linearSamplerBinding bindSampler: 0 sampler: linearSampler
]

{ #category : #initialization }
FormSGAGPUDrawCommandProcessorContext >> createShaderSignature [
	shaderSignature := device createShaderSignatureBuilder
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_SAMPLER bindingPointCount: 1;

		beginBindingBank: 100;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_UNIFORM_BUFFER bindingPointCount: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_UNIFORM_BUFFER bindingPointCount: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_UNIFORM_BUFFER bindingPointCount: 1;

		beginBindingBank: 1000;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_SAMPLED_IMAGE bindingPointCount: 1;
		
		"viewBoxTransformIndex" addBindingConstant;
		"gradientIndex" addBindingConstant;
		"colorGamma" addBindingConstant;
		"fontGamma" addBindingConstant;
		build
]

{ #category : #initialization }
FormSGAGPUDrawCommandProcessorContext >> createVertexLayout [
	| layoutSpec strideBuffer |
	layoutSpec := 
		(AGPUVertexAttribDescription new
			binding: 0;
			format: AGPU_TEXTURE_FORMAT_R32G32_FLOAT;
			offset: 0;
			getHandle) ,
		(AGPUVertexAttribDescription new
			binding: 1;
			format: AGPU_TEXTURE_FORMAT_R32G32B32A32_FLOAT;
			offset: 8;
			getHandle),
		(AGPUVertexAttribDescription new
			binding: 2;
			format: AGPU_TEXTURE_FORMAT_R32G32_FLOAT;
			offset: 24;
			getHandle).
	
	strideBuffer := ByteArray new: 4.
	strideBuffer uint32AtOffset: 0 put: 32.
	
	vertexLayout := device createVertexLayout.
	vertexLayout addVertexAttributeBindings: 1 vertex_strides: strideBuffer attribute_count: 3 attributes: (AGPUVertexAttribDescription fromHandle: layoutSpec)

]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> defaultRenderPass [
	^ defaultRenderPass
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> device [
	^ device
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> fontGamma [
	^ self hasColorCorrection ifTrue: [ 1.0 / 2.2 ] ifFalse: [1.0]
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> fontTextureAtlasCache [
	^ fontTextureAtlasCache ifNil: [ fontTextureAtlasCache := FormSGFontTextureAtlasCache new ]
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> fontTextureAtlasCache: aFontTextureAtlasCache [
	fontTextureAtlasCache := aFontTextureAtlasCache
]

{ #category : #shaders }
FormSGAGPUDrawCommandProcessorContext >> fullyOpaqueTexturedFragmentShader [
	^ '
#version 450

layout(location=0) in vec4 inColor;	
layout(location=1) in vec2 inTexcoord;

layout(location=0) out vec4 outColor;
	
layout (set=2, binding = 0) uniform texture2D activeTexture;
layout (set=0, binding = 0) uniform sampler activeSampler;

void main()
{ 
	outColor = vec4(inColor.rgb * texture(sampler2D(activeTexture, activeSampler), inTexcoord).rgb, 1.0);
}

'
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> fullyOpaqueTexturedPipelineState [

	^ fullyOpaqueTexturedPipelineState
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> hasColorCorrection [
	^ hasColorCorrection ifNil: [ hasColorCorrection := self class hasColorCorrection ]
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> hasColorCorrection: aBoolean [
	hasColorCorrection := aBoolean
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> hasTopLeftNdcOrigin [

	^ hasTopLeftNdcOrigin
]

{ #category : #initialization }
FormSGAGPUDrawCommandProcessorContext >> initializeWithDevice: theDevice [
	device := theDevice.
	
	hasTopLeftNdcOrigin := device hasTopLeftNdcOrigin ~= 0.
	projectionInvertedY := hasTopLeftNdcOrigin.

	defaultRenderPass := self createRenderPassWithColor: Color transparent.
	self
		createShaderSignature;
		createSampler;
		createVertexLayout;
		createPipelineStates.

	textureFromFormDictionary := WeakKeyDictionary new.
	textureWithModificationCountDictionary := WeakKeyDictionary new.
	renderTargetDictionary := WeakKeyDictionary new.
]

{ #category : #shaders }
FormSGAGPUDrawCommandProcessorContext >> linearGradientFragmentShader [
	^ '
#version 450

layout(location=0) in vec4 inColor;
layout(location=1) in vec2 inTexcoord;
layout(location=0) out vec4 outColor;

struct LinearGradient {
	vec2 startPoint;
	vec2 endPoint;

	vec4 startColor;
	vec4 endColor;
};

layout(set=1, binding=1, std140) uniform LinearGradients { 
	LinearGradient linearGradients[1000];
};	

layout(push_constant) uniform Indices { 
	uint viewBoxTransformIndex;
	uint gradientIndex;
	float colorGamma;
};

void main()
{ 
	LinearGradient gradient = linearGradients[gradientIndex];
	vec2 gradientVector = gradient.endPoint - gradient.startPoint;
	float alpha = dot(inTexcoord - gradient.startPoint, gradientVector) / max(dot(gradientVector, gradientVector), 0.000001);

	vec4 startColor = vec4(pow(gradient.startColor.rgb, vec3(colorGamma)), gradient.startColor.a);
	vec4 endColor = vec4(pow(gradient.endColor.rgb, vec3(colorGamma)), gradient.endColor.a);
	vec4 resultColor = mix(startColor, endColor, alpha);

	outColor = vec4(resultColor.rgb*resultColor.a, resultColor.a);
}

'
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> linearGradientPipelineState [

	^ linearGradientPipelineState
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> linearSampler [

	^ linearSampler
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> linearSamplerBinding [

	^ linearSamplerBinding
]

{ #category : #shaders }
FormSGAGPUDrawCommandProcessorContext >> premultipliedTexturedFragmentShader [
	^ '
#version 450

layout(location=0) in vec4 inColor;	
layout(location=1) in vec2 inTexcoord;

layout(location=0) out vec4 outColor;
	
layout (set=2, binding = 0) uniform texture2D activeTexture;
layout (set=0, binding = 0) uniform sampler activeSampler;

void main()
{ 
	vec4 color = inColor * texture(sampler2D(activeTexture, activeSampler), inTexcoord);
	outColor = vec4(color.rgb*inColor.a, color.a);
}

'
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> premultipliedTexturedPipelineState [

	^ premultipliedTexturedPipelineState
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> projectionInvertedY [

	^ projectionInvertedY
]

{ #category : #shaders }
FormSGAGPUDrawCommandProcessorContext >> radialGradientFragmentShader [
	^ '
#version 450

layout(location=0) in vec4 inColor;
layout(location=1) in vec2 inTexcoord;
layout(location=0) out vec4 outColor;

struct RadialGradient {
	vec2 center;
	vec2 focalPoint;

	float clipInnerRadius;
	float innerRadius;
	float outerRadius;
	float clipOuterRadius;

	vec4 startColor;
	vec4 endColor;
};

layout(set=1, binding=1, std140) uniform RadialGradients { 
	RadialGradient radialGradients[1000];
};	

layout(push_constant) uniform Indices { 
	uint viewBoxTransformIndex;
	uint gradientIndex;
	float colorGamma;
};

void main()
{ 
	RadialGradient gradient = radialGradients[gradientIndex];
	float radius = (length(inTexcoord - gradient.center) + length(inTexcoord - gradient.focalPoint))*0.5;
	if (radius < gradient.clipInnerRadius || radius > gradient.clipOuterRadius)
		discard;

	float alpha = clamp((radius - gradient.innerRadius) / max(gradient.outerRadius - gradient.innerRadius, 0.00001), 0.0, 1.0);

	vec4 startColor = vec4(pow(gradient.startColor.rgb, vec3(colorGamma)), gradient.startColor.a);
	vec4 endColor = vec4(pow(gradient.endColor.rgb, vec3(colorGamma)), gradient.endColor.a);
	vec4 resultColor = mix(startColor, endColor, alpha);

	outColor = vec4(resultColor.rgb*resultColor.a, resultColor.a);
}

'
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> radialGradientPipelineState [

	^ radialGradientPipelineState
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> renderTargetDictionary [

	^ renderTargetDictionary
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> shaderSignature [
	^ shaderSignature
]

{ #category : #shaders }
FormSGAGPUDrawCommandProcessorContext >> subpixelFragmentShader [
	^ '
#version 450

layout(location=0) in vec4 inColor;	
layout(location=1) in vec2 inTexcoord;

layout(location=0, index = 0) out vec4 outColor;
layout(location=0, index = 1) out vec4 outColorMask;

layout (set=2, binding = 0) uniform texture2D activeTexture;
layout (set=0, binding = 0) uniform sampler activeSampler;

layout(push_constant) uniform Indices { 
	uint viewBoxTransformIndex;
	uint gradientIndex;
	float colorGamma;
	float fontGamma;
};

void main()
{ 
	vec3 colorMask = pow(texture(sampler2D(activeTexture, activeSampler), inTexcoord).rgb, vec3(fontGamma));
	float alpha = max(colorMask.r, max(colorMask.g, colorMask.b));

	outColor = vec4(inColor.rgb*colorMask, alpha);
	outColorMask = vec4(colorMask, alpha);
}

'
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> subpixelPipelineState [

	^ subpixelPipelineState
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> textureFromFormDictionary [

	^ textureFromFormDictionary
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> textureWithModificationCountDictionary [

	^ textureWithModificationCountDictionary
]

{ #category : #shaders }
FormSGAGPUDrawCommandProcessorContext >> texturedFragmentShader [
	^ '
#version 450

layout(location=0) in vec4 inColor;	
layout(location=1) in vec2 inTexcoord;

layout(location=0) out vec4 outColor;
	
layout (set=2, binding = 0) uniform texture2D activeTexture;
layout (set=0, binding = 0) uniform sampler activeSampler;

void main()
{ 
	vec4 color = inColor * texture(sampler2D(activeTexture, activeSampler), inTexcoord);
	outColor = vec4(color.rgb*color.a, color.a);
}

'
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> texturedPipelineState [

	^ texturedPipelineState
]

{ #category : #accessing }
FormSGAGPUDrawCommandProcessorContext >> vertexLayout [
	^ vertexLayout
]

{ #category : #shaders }
FormSGAGPUDrawCommandProcessorContext >> vertexShader [
	^ '
#version 450
layout(location=0) in vec2 inPosition;
layout(location=1) in vec4 inColor;
layout(location=2) in vec2 inTexcoord;

layout(location=0) out vec4 outColor;
layout(location=1) out vec2 outTexcoord;

layout(set=1, binding=0, std140) uniform ViewBoxTransforms { 
	vec4 viewBoxTransforms[1000];
};	

layout(push_constant) uniform Indices { 
	uint viewBoxTransformIndex;
	uint gradientIndex;
	float colorGamma;
};

void main()
{
	vec4 viewBoxTransform = viewBoxTransforms[viewBoxTransformIndex];
	outColor = vec4(pow(inColor.rgb, vec3(colorGamma)), inColor.a);
	outTexcoord = inTexcoord;
	gl_Position = vec4(inPosition*viewBoxTransform.xy + viewBoxTransform.zw, 0.0, 1.0);
}

'

]