# Copyright 2012-2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

helpers = require('./helpers')
transform = require('../bundle-transform')
bundleHelpers = require('../bundle-helpers')

# Stream and transform helpers

runTransform = (tr, data, cb) ->
  err = null; out = null
  s = helpers.stringstream()
  tr.on('error', (e) -> err = e).on('end', -> out = s.data)
  tr.pipe(s)
  runs -> tr.end(data)
  waitsFor -> out || err
  runs -> cb(err, out)

# Bundle helpers

servicesFile = bundleHelpers.servicesFile
header = 'var AWS = require("./core"); module.exports = AWS;'
buildBundle = (services) ->
  data = [header]
  Object.keys(services).forEach (s) ->
    services[s].forEach (v) ->
      line = "AWS.Service.defineServiceApi(" +
        "require(\"./services/#{s}\"), \"#{v}\", " +
        "require(\"./services/api/#{s}-#{v}\"));"
      data.push(line)
  data.join('\n')
defaultBundle = buildBundle
  dynamodb: ['2012-08-10']
  s3:['2006-03-01']
  sqs: ['2012-11-05']
  sns: ['2010-03-31']
  sts: ['2011-06-15']

# Assertions

assertBundle = (services, bundle, errMsg) ->
  runTransform transform(services, true)(servicesFile), 'data', (err, data) ->
    expect(err).toEqual(null)
    expect(data).toEqual(bundle)

assertBundleFailed = (services, errMsg) ->
  runTransform transform(services, true)(servicesFile), 'data', (err) ->
    expect(err.message).toEqual(errMsg)

describe 'bundle transformer', ->
  beforeEach ->
    spyOn(process, 'env').andReturn({})

  it 'returns transform function if called with servicesPassed', ->
    expect(typeof transform('s3', true)).toEqual 'function'

  it 'calls transform function if not called with servicesPassed', ->
    expect(transform('filename').readable).toEqual true

  it 'does not modify output of files not named lib/aws.js', ->
    runTransform transform('foo.js'), 'foo', (e, data) ->
      expect(e).toEqual(null)
      expect(data).toEqual 'foo'

  it 'returns bundle if file is aws.js', ->
    runTransform transform(servicesFile), 'data', (e, data) ->
      expect(e).toEqual(null)
      expect(data).toEqual(defaultBundle)

  it 'uses SERVICES environment variable if services not initialized', ->
    process.env.SERVICES = 's3,cloudwatch'
    bundle = buildBundle s3: ['2006-03-01'], cloudwatch: ['2010-08-01']
    runTransform transform(servicesFile), 'data', (e, data) ->
      expect(e).toEqual(null)
      expect(data).toEqual(bundle)

  it 'accepts comma delimited services by name', ->
    services = 's3,cloudwatch'
    bundle = buildBundle s3: ['2006-03-01'], cloudwatch: ['2010-08-01']
    assertBundle(services, bundle)

  it 'uses latest service version if version suffix is not supplied', ->
    services = 'rds'
    bundle = buildBundle rds: helpers.apiFilesMap.rds[-1..-1]
    assertBundle(services, bundle)

  it 'accepts fully qualified service-version pair', ->
    services = 'rds-2013-05-15'
    bundle = buildBundle rds: ['2013-05-15']
    assertBundle(services, bundle)

  it 'accepts "all" for all services', ->
    services = 'all'
    bundle = buildBundle helpers.apiFilesMap
    assertBundle(services, bundle)

  it 'throws an error if the service does not exist', ->
    assertBundleFailed 'invalidmodule', 'Missing modules: invalidmodule'

  it 'throws an error if the service version does not exist', ->
    services = 's3-1999-01-01'
    msg = 'Missing modules: s3-1999-01-01'
    assertBundleFailed(services, msg)

  it 'groups multiple errors into one error object', ->
    services = 's3-1999-01-01,invalidmodule,dynamodb-01-01-01'
    msg = 'Missing modules: s3-1999-01-01, invalidmodule, dynamodb-01-01-01'
    assertBundleFailed(services, msg)

  it 'throws an opaque error if special characters are found (/, ., *)', ->
    msg = 'Incorrectly formatted service names'
    assertBundleFailed('path/to/service', msg)
    assertBundleFailed('to/../../../root', msg)
    assertBundleFailed('*.js', msg)
    assertBundleFailed('a.b', msg)
    assertBundleFailed('!d', msg)
    assertBundleFailed('valid1,valid2,invalid.module', msg)

  it 'returns error to callback if passed', ->
    err = null; tr = null
    services = 'invalidmodule'
    runs ->
      transform services, true, (e, t) -> err = e; tr = t
    waitsFor -> err || tr
    runs ->
      expect(err.message).toEqual('Missing modules: invalidmodule')
      runTransform tr(servicesFile), 'data', (e, out) ->
        expect(e.message).toEqual(err.message)
        expect(out).toEqual(null)
