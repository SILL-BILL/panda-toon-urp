# Panda Toon URP

Unity 6.5 / Universal Render Pipeline (URP) 向けの、キャラクター用2段階 Toon Shaderです。
古いシェーダーの移植ではなく、URP 17.5 の Shader Library を使った最小構成として実装しています。

## 対応環境

- Unity 6000.5.8f1（Unity 6.5）
- Universal Render Pipeline 17.5.0
- Forward Rendering

Shader の表示名は `Panda/URP/Panda Toon` です。

## 使用方法

1. Material を新規作成します。
2. Shader に `Panda/URP/Panda Toon` を指定します。
3. Mesh Renderer / Skinned Mesh Renderer に Material を割り当てます。
4. シーンの Main Light に Directional Light を設定し、必要なら Shadows を有効にします。
5. URP Asset でも Main Light Shadows と Shadow Distance が有効になっていることを確認します。

## パラメータ

| パラメータ | 意味 |
|---|---|
| Base Map | ベースとなるカラーテクスチャ |
| Base Color | Base Map に乗算する色 |
| Shadow Color | 影側で Base Color に乗算する色 |
| Shadow Threshold | Light / Shadow を分けるしきい値。大きいほど影が広がる |
| Shadow Boundary | 境界のぼかし幅。小さいほど硬い Toon 境界になる |
| Emission Map | 発光マスク／発光テクスチャ |
| Emission Color | Emission Map に乗算して最後に加算する HDR 対応色 |

陰影判定には `NdotL` と Main Light のリアルタイム Shadow Attenuation を使用します。
ライト色は白との中間色として反映し、強く着色したライトでも Base Color が完全に黒く潰れにくい調整です。
Main Light が存在しない、または色・強度がゼロの場合は全面を Shadow 側として扱います。
Emission は Main Light の有無に関係なく、Toon 陰影の決定後に独立して加算されます。

## 現時点で未対応

- Outline
- Rim Light
- Specular / Hair Specular
- Normal Map
- MatCap
- Additional Lights
- SSAO 専用処理
- 3段以上の影
- Alpha Clip / Transparent
- Custom Inspector / Shader GUI

## 今後追加可能な機能

3段影、Normal Map、Specular、Rim Light、Outline、Additional Lights、Alpha Clip、Transparent を、
初版の動作確認後に個別機能として段階的に追加できます。

## ライセンス

MIT License。実装コードは本リポジトリ向けの新規実装で、他の Toon Shader OSS からのコード流用はありません。
