require 'xcodeproj'

project_path = '/Users/justinseo/Desktop/fastblog/fastblog.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main app target
target = project.targets.find { |t| t.name == 'Bloggo' }

# Find groups
services_group = project.main_group.find_subpath(File.join('fastblog', 'Services'), true)
views_group = project.main_group.find_subpath(File.join('fastblog', 'Views'), true)

# File paths
pdf_service_path = '/Users/justinseo/Desktop/fastblog/fastblog/Services/PDFExportService.swift'
map_helper_path = '/Users/justinseo/Desktop/fastblog/fastblog/Services/MapSnapshotHelper.swift'
pdf_view_path = '/Users/justinseo/Desktop/fastblog/fastblog/Views/BlogPDFView.swift'

# Add to groups
pdf_service_ref = services_group.new_reference(pdf_service_path)
map_helper_ref = services_group.new_reference(map_helper_path)
pdf_view_ref = views_group.new_reference(pdf_view_path)

# Add to target
target.source_build_phase.add_file_reference(pdf_service_ref)
target.source_build_phase.add_file_reference(map_helper_ref)
target.source_build_phase.add_file_reference(pdf_view_ref)

project.save
puts "Successfully added PDF files to Xcode project."
