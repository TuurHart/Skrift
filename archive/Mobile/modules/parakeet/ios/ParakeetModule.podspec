Pod::Spec.new do |s|
  s.name           = 'ParakeetModule'
  s.version        = '0.0.1'
  s.summary        = 'On-device Parakeet TDT v3 transcription via FluidAudio'
  s.description    = 'Expo module exposing FluidAudio ASR to React Native'
  s.author         = ''
  s.homepage       = 'https://github.com/FluidInference/FluidAudio'
  s.license        = 'MIT'
  s.platforms      = { :ios => '17.0' }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  }

  s.source_files = '**/*.{h,m,mm,swift,hpp,cpp}'

  # FluidAudio via Swift Package Manager — RN 0.75+ exposes `spm_dependency`
  # to declare SPM deps from a pod and wire the module search paths correctly.
  # Requires `use_frameworks!` in the host Podfile (set via
  # Podfile.properties.json: "ios.useFrameworks": "static").
  spm_dependency(s,
    url: 'https://github.com/FluidInference/FluidAudio.git',
    requirement: { kind: 'exactVersion', version: '0.12.4' },
    products: ['FluidAudio']
  )
end
