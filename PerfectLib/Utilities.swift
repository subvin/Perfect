//
//  Utilities.swift
//  PerfectLib
//
//  Created by Kyle Jessup on 7/17/15.
//	Copyright (C) 2015 PerfectlySoft, Inc.
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU Affero General Public License as
//	published by the Free Software Foundation, either version 3 of the
//	License, or (at your option) any later version, as supplemented by the
//	Perfect Additional Terms.
//
//	This program is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU Affero General Public License, as supplemented by the
//	Perfect Additional Terms, for more details.
//
//	You should have received a copy of the GNU Affero General Public License
//	and the Perfect Additional Terms that immediately follow the terms and
//	conditions of the GNU Affero General Public License along with this
//	program. If not, see <http://www.perfect.org/AGPL_3_0_With_Perfect_Additional_Terms.txt>.
//

import Foundation

internal func split_thread(closure:()->()) {
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), closure)
}

/// This class permits an UnsafeMutablePointer to be used as a GeneratorType
public struct GenerateFromPointer<T> : GeneratorType {
	
	public typealias Element = T
	
	var count = 0
	var pos = 0
	var from: UnsafeMutablePointer<T>
	
	/// Initialize given an UnsafeMutablePointer and the number of elements pointed to.
	public init(from: UnsafeMutablePointer<T>, count: Int) {
		self.from = from
		self.count = count
	}
	
	/// Return the next element or nil if the sequence has been exhausted.
	mutating public func next() -> Element? {
		guard count > 0 else {
			return nil
		}
		self.count -= 1
		return self.from[self.pos++]
	}
}

/// A generalized wrapper around the Unicode codec operations.
public class Encoding {
	
	/// Return a String given a character generator.
	public static func encode<D : UnicodeCodecType, G : GeneratorType where G.Element == D.CodeUnit>(decoder : D, generator: G) -> String {
		var encodedString = ""
		var finished: Bool = false
		var mutableDecoder = decoder
		var mutableGenerator = generator
		repeat {
			let decodingResult = mutableDecoder.decode(&mutableGenerator)
			switch decodingResult {
			case .Result(let char):
				encodedString.append(char)
			case .EmptyInput:
				finished = true
				/* ignore errors and unexpected values */
			case .Error:
				finished = true
			}
		} while !finished
		return encodedString
	}
}

/// Utility wrapper permitting a UTF-16 character generator to encode a String.
public class UTF16Encoding {
	
	/// Use a UTF-16 character generator to create a String.
	public static func encode<G : GeneratorType where G.Element == UTF16.CodeUnit>(generator: G) -> String {
		return Encoding.encode(UTF16(), generator: generator)
	}
}

/// Utility wrapper permitting a UTF-8 character generator to encode a String. Also permits a String to be converted into a UTF-8 byte array.
public class UTF8Encoding {
	
	/// Use a character generator to create a String.
	public static func encode<G : GeneratorType where G.Element == UTF8.CodeUnit>(generator: G) -> String {
		return Encoding.encode(UTF8(), generator: generator)
	}
	
	/// Use a character sequence to create a String.
	public static func encode<S : SequenceType where S.Generator.Element == UTF8.CodeUnit>(bytes: S) -> String {
		return encode(bytes.generate())
	}
	
	/// Decode a String into an array of UInt8.
	public static func decode(str: String) -> Array<UInt8> {
		return Array<UInt8>(str.utf8)
	}
}

extension UInt8 {
	private var shouldURLEncode: Bool {
		let cc = self
		return ( ( cc >= 128 )
			|| ( cc < 33 )
			|| ( cc >= 34  && cc < 38 )
			|| ( ( cc > 59  && cc < 61) || cc == 62 || cc == 58)
			|| ( ( cc >= 91  && cc < 95 ) || cc == 96 )
			|| ( cc >= 123 && cc <= 126 )
			|| self == 43 )
	}
	private var hexString: String {
		var s = ""
		let b = self >> 4
		s.append(UnicodeScalar(b > 9 ? b - 10 + 65 : b + 48))
		let b2 = self & 0x0F
		s.append(UnicodeScalar(b2 > 9 ? b2 - 10 + 65 : b2 + 48))
		return s
	}
}

extension String {
	/// Returns the String with all special HTML characters encoded.
	public var stringByEncodingHTML: String {
		var ret = ""
		var g = self.unicodeScalars.generate()
		while let c = g.next() {
			if c < UnicodeScalar(0x0009) {
				ret.appendContentsOf("&#x");
				ret.append(UnicodeScalar(0x0030 + UInt32(c)));
				ret.appendContentsOf(";");
			} else if c == UnicodeScalar(0x0022) {
				ret.appendContentsOf("&quot;")
			} else if c == UnicodeScalar(0x0026) {
				ret.appendContentsOf("&amp;")
			} else if c == UnicodeScalar(0x0027) {
				ret.appendContentsOf("&#39;")
			} else if c == UnicodeScalar(0x003C) {
				ret.appendContentsOf("&lt;")
			} else if c == UnicodeScalar(0x003E) {
				ret.appendContentsOf("&gt;")
			} else if c > UnicodeScalar(126) {
				ret.appendContentsOf("&#\(UInt32(c));")
			} else {
				ret.append(c)
			}
		}
		return ret
	}
	
	/// Returns the String with all special URL characters encoded.
	public var stringByEncodingURL: String {
		var ret = ""
		var g = self.utf8.generate()
		while let c = g.next() {
			if c.shouldURLEncode {
				ret.append(UnicodeScalar(37))
				ret.appendContentsOf(c.hexString)
			} else {
				ret.append(UnicodeScalar(c))
			}
		}
		return ret
	}
}

extension String {
	
	/// Parse an HTTP Digest authentication header returning a Dictionary containing each part.
	public func parseAuthentication() -> [String:String] {
		var ret = [String:String]()
		if let _ = self.rangeOfString("Digest ") {
			ret["type"] = "Digest"
			let wantFields = ["username", "nonce", "nc", "cnonce", "response", "uri", "realm", "qop", "algorithm"]
			for field in wantFields {
				if let foundField = String.extractField(self, named: field) {
					ret[field] = foundField
				}
			}
		}
		return ret
	}
	
	private static func extractField(from: String, named: String) -> String? {
		guard let range = from.rangeOfString(named + "=") else {
			return nil
		}
		
		var currPos = range.endIndex
		var ret = ""
		let quoted = from[currPos] == "\""
		if quoted {
			currPos = currPos.successor()
			let tooFar = from.endIndex
			while currPos != tooFar {
				if from[currPos] == "\"" {
					break
				}
				ret.append(from[currPos])
				currPos = currPos.successor()
			}
		} else {
			let tooFar = from.endIndex
			while currPos != tooFar {
				if from[currPos] == "," {
					break
				}
				ret.append(from[currPos])
				currPos = currPos.successor()
			}
		}
		return ret
	}
}

extension String {
	
	var pathSeparator: UnicodeScalar {
		return UnicodeScalar(47)
	}
	
	var extensionSeparator: UnicodeScalar {
		return UnicodeScalar(46)
	}
	
	private var beginsWithSeparator: Bool {
		let unis = self.characters
		guard unis.count > 0 else {
			return false
		}
		return unis[unis.startIndex] == Character(pathSeparator)
	}
	
	private var endsWithSeparator: Bool {
		let unis = self.characters
		guard unis.count > 0 else {
			return false
		}
		return unis[unis.endIndex.predecessor()] == Character(pathSeparator)
	}
	
	private func pathComponents(addFirstLast: Bool) -> [String] {
		var r = [String]()
		let unis = self.characters
		guard unis.count > 0 else {
			return r
		}
		
		if addFirstLast && self.beginsWithSeparator {
			r.append(String(pathSeparator))
		}
		
		r.appendContentsOf(self.characters.split(Character(pathSeparator)).map { String($0) })
		
		if addFirstLast && self.endsWithSeparator {
			r.append(String(pathSeparator))
		}
		return r
	}
	
	var pathComponents: [String] {
		return self.pathComponents(true)
	}
	
	var lastPathComponent: String {
		let last = self.pathComponents(false).last ?? ""
		if last.isEmpty && self.characters.first == Character(pathSeparator) {
			return String(pathSeparator)
		}
		return last
	}
	
	var stringByDeletingLastPathComponent: String {
		var comps = self.pathComponents(false)
		guard comps.count > 1 else {
			if self.beginsWithSeparator {
				return String(pathSeparator)
			}
			return ""
		}
		comps.removeLast()
		let joined = comps.joinWithSeparator(String(pathSeparator))
		if self.beginsWithSeparator {
			return String(pathSeparator) + joined
		}
		return joined
	}
	
	var stringByDeletingPathExtension: String {
		let unis = self.characters
		let startIndex = unis.startIndex
		var endIndex = unis.endIndex
		while endIndex != startIndex {
			if unis[endIndex.predecessor()] != Character(pathSeparator) {
				break
			}
			endIndex = endIndex.predecessor()
		}
		let noTrailsIndex = endIndex
		while endIndex != startIndex {
			endIndex = endIndex.predecessor()
			if unis[endIndex] == Character(extensionSeparator) {
				break
			}
		}
		guard endIndex != startIndex else {
			if noTrailsIndex == startIndex {
				return self
			}
			return self.substringToIndex(noTrailsIndex)
		}
		return self.substringToIndex(endIndex)
	}
	
	var pathExtension: String {
		let unis = self.characters
		let startIndex = unis.startIndex
		var endIndex = unis.endIndex
		while endIndex != startIndex {
			if unis[endIndex.predecessor()] != Character(pathSeparator) {
				break
			}
			endIndex = endIndex.predecessor()
		}
		let noTrailsIndex = endIndex
		while endIndex != startIndex {
			endIndex = endIndex.predecessor()
			if unis[endIndex] == Character(extensionSeparator) {
				break
			}
		}
		guard endIndex != startIndex else {
			return ""
		}
		return self.substringWithRange(Range(start:endIndex.successor(), end:noTrailsIndex))
	}

	var stringByResolvingSymlinksInPath: String {
		let absolute = self.beginsWithSeparator
		let components = self.pathComponents(false)
		var s = absolute ? "/" : ""
		for component in components {
			if component == "." {
				s.appendContentsOf(".")
			} else if component == ".." {
				s.appendContentsOf("..")
			} else {
				let file = File(s + "/" + component)
				s = file.realPath()
			}
		}
		let ary = s.pathComponents(false) // get rid of slash runs
		return absolute ? "/" + ary.joinWithSeparator(String(pathSeparator)) : ary.joinWithSeparator(String(pathSeparator))
	}
}
















