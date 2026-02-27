require 'xcodeproj'

begin
  project_path = '/Users/justinseo/Desktop/fastblog/fastblog.xcodeproj'
  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == 'fastblog' }
  source_build_phase = target.source_build_phase

  files_in_project = source_build_phase.files.map do |build_file|
    begin
      build_file.file_ref.real_path.to_s
    rescue
      nil
    end
  end.compact

  missing_files = []
  Dir.glob('/Users/justinseo/Desktop/fastblog/fastblog/Services/*.swift').each do |file|
    unless files_in_project.include?(file)
      missing_files << file
    end
  end

  puts "MISSING_FILES:"
  missing_files.each { |f| puts f }
rescue => e
  puts "ERROR: #{e.message}"
end
