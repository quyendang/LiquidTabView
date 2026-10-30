# Shader source

`liquidLens.metal` is the source of the icon shader embedded in `LiquidTabView.swift`. You do not need to add this file to your app to use the component.

The SwiftUI component uses two Metal libraries compiled separately for iPhone and Simulator, targeting iOS 26.0 or later, and stored as Base64 in `LiquidLensShader`. If you change the shader, recompile it for both targets and replace both data blocks. Changing the Swift tint, icons, or tabs does not require recompilation of the shader.

Android keeps its AGSL source directly in `LiquidTabView.kt`. The shaders share the same refraction approach; neither is Apple's internal shader code or an algorithm supplied by Apple.
