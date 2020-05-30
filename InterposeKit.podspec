Pod::Spec.new do |s|
  s.name                      = 'InterposeKit'
  s.version                   = '0.0.1'
  s.summary                   = 'A modern library to swizzle elegantly in Swift.'
  s.homepage                  = 'https://github.com/steipete/InterposeKit'
  s.source                    = { :git => s.homepage + '.git', :tag => s.version }
  s.license                   = { :type => 'MIT', :file => 'LICENSE' }
  s.authors                   = { 'Peter Steinberger' => 'steipete@gmail.com' }
  s.source_files              = 'Sources/**/*.{h,c,swift}'
  s.swift_versions            = ['5.2']
  s.pod_target_xcconfig       = { 'APPLICATION_EXTENSION_API_ONLY' => 'YES' }
  s.ios.deployment_target     = '11.0'
  s.osx.deployment_target     = '10.13'
  s.tvos.deployment_target    = '11.0'
  s.watchos.deployment_target = '5.0'
end