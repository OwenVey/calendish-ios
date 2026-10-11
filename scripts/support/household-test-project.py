"""Build a separate simulator harness from production sources and locked dependencies."""
import json
import pathlib
import subprocess
import sys

# Usage: household-test-project.py [test-file harness-dir product bundle-id]
test_file, harness, product, bundle = sys.argv[1:5] if len(sys.argv) > 4 else (
    'tests/Account/HouseholdStoreWorkflowTests.swift', 'household-workflow', 'HouseholdWorkflow', 'owenvey.calendish-household-workflow')
root = pathlib.Path(__file__).resolve().parents[2]
dest = root / '.build' / harness / 'Workflow.xcodeproj'
dest.mkdir(parents=True, exist_ok=True)
converted = dest.parent / 'project.json'
subprocess.run(['plutil', '-convert', 'json', '-o', str(converted), str(root / 'calendish.xcodeproj/project.pbxproj')], check=True)
project = json.loads(converted.read_text())
objects = project['objects']
target_id = '05BDE75B3072DA7B00C5B9A0'
project_object = objects[project['rootObject']]
project_object['targets'] = [target_id]
project_object['projectDirPath'] = str(root)
target = objects[target_id]
target['dependencies'] = []
target['buildPhases'].remove('5E0A11CE000000000000000B')
target['name'] = target['productName'] = product
for obj in objects.values():
    if obj.get('isa') == 'PBXFileSystemSynchronizedRootGroup':
        obj['path'] = str(root / obj['path'])
for config in objects[target['buildConfigurationList']]['buildConfigurations']:
    settings = objects[config]['buildSettings']
    settings.update(PRODUCT_BUNDLE_IDENTIFIER=bundle, PRODUCT_NAME=product,
                    GENERATE_INFOPLIST_FILE='YES', CODE_SIGNING_ALLOWED='NO', ASSETCATALOG_COMPILER_APPICON_NAME='')
    settings.pop('CODE_SIGN_ENTITLEMENTS', None)
    settings.pop('INFOPLIST_FILE', None)
objects['05BDE7763072DA7C00C5B9A0']['membershipExceptions'].append('App/CalendishApp.swift')
file_id, build_id = 'ABCDEF000000000000000001', 'ABCDEF000000000000000002'
objects[file_id] = dict(isa='PBXFileReference', lastKnownFileType='sourcecode.swift',
                        path=str(root / test_file), sourceTree='<absolute>')
objects[build_id] = dict(isa='PBXBuildFile', fileRef=file_id)
objects['05BDE7583072DA7B00C5B9A0']['files'].append(build_id)
objects['05BDE7533072DA7B00C5B9A0']['children'].append(file_id)
if test_file == 'tests/Account/HouseholdStoreWorkflowTests.swift':
    contract_file, contract_build = 'ABCDEF000000000000000003', 'ABCDEF000000000000000004'
    objects[contract_file] = dict(isa='PBXFileReference', lastKnownFileType='sourcecode.swift',
                                 path=str(root / 'tests/Data/SupabaseHouseholdBackendContractTests.swift'), sourceTree='<absolute>')
    objects[contract_build] = dict(isa='PBXBuildFile', fileRef=contract_file)
    objects['05BDE7583072DA7B00C5B9A0']['files'].append(contract_build)
    objects['05BDE7533072DA7B00C5B9A0']['children'].append(contract_file)
objects['05BDE75A3072DA7B00C5B9A0']['files'] = []
path = dest / 'project.pbxproj'
path.write_text(json.dumps(project))
subprocess.run(['plutil', '-convert', 'xml1', str(path)], check=True)
# Pin the harness to the app's checked-in dependency versions.
workspace = dest / 'project.xcworkspace/xcshareddata/swiftpm'
workspace.mkdir(parents=True, exist_ok=True)
(workspace / 'Package.resolved').write_bytes((root / 'calendish.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_bytes())
