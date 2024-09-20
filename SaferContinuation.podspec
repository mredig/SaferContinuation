#
# Be sure to run `pod lib lint StackKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SaferContinuation'
  s.version          = '1.3.2'
  s.summary          = 'Make porting async/await from older methods even safer by providing some mechanisms around Continuations communicating when failure occurs.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = """
  This is meant to make porting async/await from older methods even safer by providing some mechanisms around Continuations communicating when failure occurs.

  It is either entirely unecessary or fills in some gaps (I'm aware of the Unsafe and Checked-Continuation types, but CheckedContinuation seemingly leaves some things to be desired in my opinion) and provides some assistance while migrating code to async/await and includes some troubleshooting tools.

  I'm certain that it adds a non-trivial amount of overhead (to async code), but should allow for safer migration from older async code. I have not tested to compare performance metrics between this and the existing types.
  """

  s.homepage         = 'https://github.com/mredig/SaferContinuation'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'mredig' => 'xxx@xxx.xx' }
  s.source           = { :git => 'https://github.com/mredig/SaferContinuation', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'

  s.source_files = 'Sources/SaferContinuation/**/*'

  s.dependency 'Swiftwood'

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/SaferContinuationTests/**/*'
  end

end
