Pod::Spec.new do |s|

  s.name         = "FGTranslator"
  s.version      = "1.1.2"
  s.summary      = "iOS library for Google and Bing translation services"
  s.homepage     = "https://github.com/gpolak/FGTranslator"
  s.license      = { :type => "MIT", :file => "LICENSE" }

  s.author       = { "George Polak" => "george.polak@gmail.com" }

  s.ios.deployment_target = "7.0"
  s.osx.deployment_target = "10.9"

  s.source       = { :git => "https://github.com/gpolak/FGTranslator.git", :tag => "1.1.2" }

  s.source_files = 'FGTranslator', 'FGTranslator/XMLDictionary'
  s.requires_arc = true

  s.dependency 'AFNetworking', '~> 2.0'
  s.dependency 'PINCache'

end
