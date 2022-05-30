
Pod::Spec.new do |s|
  s.name             = 'LRException'
  s.version          = '0.1.1'
  s.summary          = 'A short description of LRException.'
  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC
  s.homepage         = 'https://github.com/huawt/LRException'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'huawt' => 'ghost263sky@163.com' }
  s.source           = { :git => 'https://github.com/huawt/LRException.git', :tag => s.version.to_s }
  s.ios.deployment_target = '9.0'
  s.source_files = 'LRException/Classes/**/*'
end
