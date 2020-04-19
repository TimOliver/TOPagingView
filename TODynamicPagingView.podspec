Pod::Spec.new do |s|
  s.name     = 'TODynamicPagingView'
  s.version  = '1.0.1'
  s.license  =  { :type => 'MIT', :file => 'LICENSE' }
  s.summary  = 'A paging scroll view that can handle arbitrary numbers of page views at run-time.'
  s.homepage = 'https://github.com/TimOliver/TODynamicPagingView'
  s.author   = 'Tim Oliver'
  s.source   = { :git => 'https://github.com/TimOliver/TODynamicPagingView.git', :tag => s.version }
  s.platform = :ios, '8.0'
  s.source_files = 'TODynamicPagingView/**/*.{h,m}'
  s.requires_arc = true
end
