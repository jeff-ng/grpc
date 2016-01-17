#!/usr/bin/env ruby

# Copyright 2015, Google Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#     * Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
# copyright notice, this list of conditions and the following disclaimer
# in the documentation and/or other materials provided with the
# distribution.
#     * Neither the name of Google Inc. nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Sample app that connects to a Route Guide service.
#
# Usage: $ path/to/route_guide_client.rb path/to/route_guide_db.json &

this_dir = File.expand_path(File.dirname(__FILE__))
lib_dir = File.join(File.dirname(this_dir), 'lib')
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)

require 'grpc'
require 'route_guide_services'

include Routeguide

GET_FEATURE_POINTS = [
  Point.new(latitude:  409_146_138, longitude: -746_188_906),
  Point.new(latitude:  0, longitude: 0)
]

# runs a GetFeature rpc.
#
# - once with a point known to be present in the sample route database
# - once with a point that is not in the sample database
def run_get_feature(stub)
  p 'GetFeature'
  p '----------'
  GET_FEATURE_POINTS.each do |pt|
    resp = stub.get_feature(pt)
    if resp.name != ''
      p "- found '#{resp.name}' at #{pt.inspect}"
    else
      p "- found nothing at #{pt.inspect}"
    end
  end
end

LIST_FEATURES_RECT = Rectangle.new(
  lo: Point.new(latitude: 400_000_000, longitude: -750_000_000),
  hi: Point.new(latitude: 420_000_000, longitude: -730_000_000))

# runs a ListFeatures rpc.
#
# - the rectangle to chosen to include most of the known features
#   in the sample db.
def run_list_features(stub)
  p 'ListFeatures'
  p '------------'
  resps = stub.list_features(LIST_FEATURES_RECT)
  resps.each do |r|
    p "- found '#{r.name}' at #{r.location.inspect}"
  end
end

# RandomRoute provides an Enumerable that yields a random 'route' of points
# from a list of Features.
class RandomRoute
  def initialize(features, size)
    @features = features
    @size = size
  end

  # yields a point, waiting between 0 and 1 seconds between each yield
  #
  # @return an Enumerable that yields a random point
  def each
    return enum_for(:each) unless block_given?
    @size.times do
      json_feature = @features[rand(0..@features.length)]
      next if json_feature.nil?
      location = json_feature['location']
      pt = Point.new(
        Hash[location.each_pair.map { |k, v| [k.to_sym, v] }])
      p "- next point is #{pt.inspect}"
      yield pt
      sleep(rand(0..1))
    end
  end
end

# runs a RecordRoute rpc.
#
# - the rectangle to chosen to include most of the known features
#   in the sample db.
def run_record_route(stub, features)
  p 'RecordRoute'
  p '-----------'
  points_on_route = 10  # arbitrary
  deadline = points_on_route  # as delay b/w each is max 1 second
  reqs = RandomRoute.new(features, points_on_route)
  resp = stub.record_route(reqs.each, deadline)
  p "summary: #{resp.inspect}"
end

ROUTE_CHAT_NOTES = [
  RouteNote.new(message: 'doh - a deer',
                location: Point.new(latitude: 0, longitude: 0)),
  RouteNote.new(message: 'ray - a drop of golden sun',
                location: Point.new(latitude: 0, longitude: 1)),
  RouteNote.new(message: 'me - the name I call myself',
                location: Point.new(latitude: 1, longitude: 0)),
  RouteNote.new(message: 'fa - a longer way to run',
                location: Point.new(latitude: 1, longitude: 1)),
  RouteNote.new(message: 'soh - with needle and a thread',
                location: Point.new(latitude: 0, longitude: 1))
]

# runs a RouteChat rpc.
#
# sends a canned set of route notes and prints out the responses.
def run_route_chat(stub)
  p 'Route Chat'
  p '----------'
  # TODO: decouple sending and receiving, i.e have the response enumerator run
  # on its own thread.
  resps = stub.route_chat(ROUTE_CHAT_NOTES)
  resps.each { |r| p "received #{r.inspect}" }
end

def main
  stub = RouteGuide::Stub.new('localhost:50051')
  run_get_feature(stub)
  run_list_features(stub)
  run_route_chat(stub)
  if ARGV.length == 0
    p 'no feature database; skipping record_route'
    exit
  end
  raw_data = []
  File.open(ARGV[0]) do |f|
    raw_data = MultiJson.load(f.read)
  end
  run_record_route(stub, raw_data)
end

main
