require 'xcodeproj'

begin
  project_path = '/Users/justinseo/Desktop/fastblog/fastblog.xcodeproj'
  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == 'fastblog' }
  source_build_phase = target.source_build_phase

  # Main group named 'fastblog'
  main_group = project.main_group.groups.find { |g| g.display_name == 'fastblog' || g.name == 'fastblog' }
  if main_group.nil?
    puts "Could not find main group 'fastblog'"
    exit 1
  end

  # The Services group
  services_group = main_group.groups.find { |g| g.display_name == 'Services' || g.name == 'Services' }
  if services_group.nil?
    services_group = main_group.new_group('Services', 'Services')
  end

  files_to_add = [
    '/Users/justinseo/Desktop/fastblog/fastblog/Services/StoryCaptionService.swift',
    '/Users/justinseo/Desktop/fastblog/fastblog/Services/LocalLLMStoryCaptionGenerator.swift',
    '/Users/justinseo/Desktop/fastblog/fastblog/Services/StoryCaptionGenerator.swift',
    '/Users/justinseo/Desktop/fastblog/fastblog/Services/PhotoTagService.swift'
  ]

  added_count = 0
  files_to_add.each do |file_path|
    # Check if the file is already in the project
    existing_ref = services_group.files.find { |f| f.real_path.to_s == file_path }
    file_ref = existing_ref || services_group.new_reference(file_path)

    # Add to the build phase if not already there
    unless source_build_phase.files.any? { |bf| bf.file_ref == file_ref }
      source_build_phase.add_file_reference(file_ref)
      puts "Added #{file_path} to target"
      added_count += 1
    else
      puts "#{file_path} is already in the target"
    end
  end

  if added_count > 0
    project.save
    puts "Saved project successfully!"
  else
    puts "No new files were added."
  end
rescue => e
  puts "ERROR: #{e.message}"
end
