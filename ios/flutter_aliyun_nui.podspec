#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_aliyun_nui.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_aliyun_nui'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.platform = :ios, '12.0'
  s.dependency 'Flutter'
  s.dependency 'AliyunIOSNuiSDK', '0.0.2'
  s.source_files = 'Classes/**/*'
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES',
  }
  s.resource_bundles = {'flutter_aliyun_nui_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
