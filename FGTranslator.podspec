Pod::Spec.new do |s|

  s.name         = "FGTranslator"
  s.version      = "1.2"
  s.summary      = "iOS library for Google and Bing translation services"
  s.description      = <<-DESC
More info about google translation here: https://cloud.google.com/translate/docs/
                       DESC
  s.homepage     = "https://github.com/b123400/FGTranslator"
  s.license      = { :type => "MIT", :file => "LICENSE" }

  s.author       = { "George Polak" => "george.polak@gmail.com", "b123400" => "https://b123400.net/" }

  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.9"

  s.source       = { :git => "https://github.com/b123400/FGTranslator.git", :tag => s.version.to_s }

  s.source_files = 'FGTranslator', 'FGTranslator/XMLDictionary'
  s.requires_arc = true

  s.dependency 'AFNetworking', '~> 2.0'
  s.dependency 'PINCache'
  s.dependency 'XMLDictionary', '~> 1.4'

end
