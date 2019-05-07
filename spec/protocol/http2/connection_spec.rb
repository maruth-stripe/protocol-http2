# Copyright, 2018, by Samuel G. D. Williams. <http://www.codeotaku.com>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require_relative 'connection_context'

RSpec.describe Protocol::HTTP2::Connection do
	include_context Protocol::HTTP2::Connection
	
	it "can negotiate connection" do
		first_server_frame = nil
		
		first_client_frame = client.send_connection_preface do
			first_server_frame = server.read_connection_preface([])
		end
		
		expect(first_client_frame).to be_kind_of Protocol::HTTP2::SettingsFrame
		expect(first_client_frame).to_not be_acknowledgement
		
		expect(first_server_frame).to be_kind_of Protocol::HTTP2::SettingsFrame
		expect(first_server_frame).to_not be_acknowledgement
		
		frame = client.read_frame
		expect(frame).to be_kind_of Protocol::HTTP2::SettingsFrame
		expect(frame).to be_acknowledgement
		
		frame = server.read_frame
		expect(frame).to be_kind_of Protocol::HTTP2::SettingsFrame
		expect(frame).to be_acknowledgement
		
		expect(client.state).to eq :open
		expect(server.state).to eq :open
	end
	
	context Protocol::HTTP2::PingFrame do
		before do
			client.open!
			server.open!
		end
		
		it "can send ping and receive pong" do
			expect(server).to receive(:receive_ping).once.and_call_original
			
			client.send_ping("12345678")
			
			server.read_frame
			
			expect(client).to receive(:receive_ping).once.and_call_original
			
			client.read_frame
		end
	end
	
	context Protocol::HTTP2::Stream do
		before do
			client.open!
			server.open!
		end
		
		let(:request_data) {"Hello World!"}
		let(:stream) {Protocol::HTTP2::Stream.new(client)}
		
		let(:request_headers) {[[':method', 'GET'], [':path', '/'], [':authority', 'localhost']]}
		let(:response_headers) {[[':status', '200']]}
		
		it "can create new stream and send response" do
			client.streams[stream.id] = stream
			stream.send_headers(nil, request_headers)
			expect(stream.id).to eq 1
			
			expect(server).to receive(:receive_headers).once.and_call_original
			server.read_frame
			expect(server.streams).to_not be_empty
			
			expect(server.streams[1].headers).to eq request_headers
			expect(server.streams[1].state).to eq :open
			
			stream.send_data(request_data, Protocol::HTTP2::END_STREAM)
			expect(stream.state).to eq :half_closed_local
			
			data_frame = server.read_frame
			expect(server.streams[1].data).to eq request_data
			expect(server.streams[1].state).to eq :half_closed_remote
			
			server.streams[1].send_headers(nil, response_headers, Protocol::HTTP2::END_STREAM)
			
			client.read_frame
			expect(stream.headers).to eq response_headers
			expect(stream.state).to eq :closed
			
			expect(stream.remote_window.used).to eq data_frame.length
		end
	end
end