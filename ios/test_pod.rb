require 'cocoapods-core'
source = Pod::Source.new('https://github.com/CocoaPods/Specs.git')
puts source.search_by_name('Tor').map(&:name)
