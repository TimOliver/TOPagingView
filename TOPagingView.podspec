Pod::Spec.new do |s|
  s.name     = 'TOPagingView'
  s.version  = '1.1.0'
  s.license  =  { :type => 'MIT', :file => 'LICENSE' }
  s.summary  = 'A paging scroll view that can handle arbitrary numbers of page views at runtime.'
  s.homepage = 'https://github.com/TimOliver/TOPagingView'
  s.author   = 'Tim Oliver'
  s.source   = { :git => 'https://github.com/TimOliver/TOPagingView.git', :tag => s.version }
  s.platform = :ios, '10.0'
  s.source_files = 'TOPagingView/**/*.{h,m}'
  s.requires_arc = true
end
