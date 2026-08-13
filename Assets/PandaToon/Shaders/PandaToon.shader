Shader "Panda/URP/Panda Toon"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _ShadowColor("Shadow Color", Color) = (0.55, 0.6, 0.75, 1)
        _ShadowThreshold("Shadow Threshold", Range(0, 1)) = 0.5
        _ShadowSmoothness("Shadow Boundary", Range(0.001, 0.5)) = 0.05
        [NoScaleOffset] _EmissionMap("Emission Map", 2D) = "white" {}
        [HDR] _EmissionColor("Emission Color", Color) = (0, 0, 0, 0)
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex PandaToonVertex
            #pragma fragment PandaToonFragment

            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_EmissionMap);
            SAMPLER(sampler_EmissionMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half4 _ShadowColor;
                half _ShadowThreshold;
                half _ShadowSmoothness;
                half4 _EmissionColor;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3 normalWS : TEXCOORD1;
                float2 uv : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            half EvaluateToonBand(half rampInput)
            {
                half halfWidth = max(_ShadowSmoothness * 0.5h, 0.0005h);
                return smoothstep(
                    _ShadowThreshold - halfWidth,
                    _ShadowThreshold + halfWidth,
                    rampInput);
            }

            Varyings PandaToonVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);

                output.positionHCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalInputs.normalWS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 PandaToonFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                half4 baseSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 baseColor = baseSample.rgb * _BaseColor.rgb;

                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                // URP 17.5 initializes the main-light color to black when no
                // main light is visible. No separate presence flag is exposed to HLSL.
                half mainLightPresent = step(
                    0.0001h,
                    max(max(mainLight.color.r, mainLight.color.g), mainLight.color.b));
                half3 normalWS = normalize(input.normalWS);
                half nDotL = saturate(dot(normalWS, mainLight.direction));

                // Shape shading and the main-light shadow map share one two-step ramp.
                half rampInput = min(nDotL, mainLight.shadowAttenuation);
                half lightBand = EvaluateToonBand(rampInput);

                half3 shadowedBase = baseColor * _ShadowColor.rgb;
                half3 toonColor = lerp(shadowedBase, baseColor, lightBand);

                // A half-strength tint preserves readability under highly saturated lights.
                half3 safeLightTint = lerp(half3(1.0h, 1.0h, 1.0h), mainLight.color, 0.5h);
                half3 litToonColor = toonColor * safeLightTint;
                half3 finalToonColor = lerp(shadowedBase, litToonColor, mainLightPresent);

                // Additional lights use a saturating coverage blend instead of additive
                // lighting. Multiple lights can fill shadowed regions without stacking
                // their full RGB values and blowing out the two-step toon result.
                half additionalCoverage = 0.0h;
                half additionalWeight = 0.0h;
                half3 additionalTintSum = half3(0.0h, 0.0h, 0.0h);

                #if defined(_ADDITIONAL_LIGHTS)
                    // LIGHT_LOOP_BEGIN requires this exact InputData variable in the
                    // clustered (Forward+) path.
                    InputData inputData = (InputData)0;
                    inputData.positionWS = input.positionWS;
                    inputData.normalWS = normalWS;
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionHCS);

                    uint pixelLightCount = GetAdditionalLightsCount();
                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light additionalLight = GetAdditionalLight(
                            lightIndex,
                            inputData.positionWS,
                            half4(1.0h, 1.0h, 1.0h, 1.0h));

                        half additionalNdotL = saturate(dot(normalWS, additionalLight.direction));
                        half toonMask = EvaluateToonBand(additionalNdotL);
                        half lightReach = saturate(
                            additionalLight.distanceAttenuation * additionalLight.shadowAttenuation);
                        half additionalInfluence = toonMask * lightReach;

                        half lightEnergy = max(
                            max(additionalLight.color.r, additionalLight.color.g),
                            additionalLight.color.b);
                        additionalInfluence *= step(0.0001h, lightEnergy);

                        half3 additionalTint = lerp(
                            half3(1.0h, 1.0h, 1.0h),
                            additionalLight.color,
                            0.5h);
                        additionalTintSum += additionalTint * additionalInfluence;
                        additionalWeight += additionalInfluence;
                        additionalCoverage = 1.0h
                            - (1.0h - additionalCoverage) * (1.0h - additionalInfluence);
                    LIGHT_LOOP_END
                #endif

                half3 additionalTint = additionalTintSum / max(additionalWeight, 0.0001h);
                half3 additionalTarget = baseColor * additionalTint;
                half3 brightenedTarget = max(finalToonColor, additionalTarget);
                finalToonColor = lerp(finalToonColor, brightenedTarget, additionalCoverage);

                half3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, input.uv).rgb
                    * _EmissionColor.rgb;

                return half4(finalToonColor + emission, baseSample.a * _BaseColor.a);
            }
            ENDHLSL
        }

        // URP's maintained opaque shadow caster pass provides self- and cast-shadow support.
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }

    FallBack Off
}
