//
//  ARISocket.swift
//  TestSwiftyCocoa
//
//  Created by Helge Heß on 6/9/14.
//  Copyright (c) 2014 Helge Hess. All rights reserved.
//

import Darwin
import Dispatch

/**
 * Simple Socket classes for Swift.
 *
 * PassiveSockets are 'listening' sockets, ActiveSockets are open connections.
 *
 * NOTE: Those would work with Generics on any type of (constant length for now)
 *       socket, but this got my swiftc crash on unimplemented features ;-)
 *
 *        Socket<T: SocketAddress>
 *
 *      and then PassiveSocket<sockaddr_in> etc. Crashes compiler.
 */
class Socket<T: SocketAddress> {
  
  var fd:           CInt?
  var boundAddress: T?
  var isValid:      Bool { return fd           != nil }
  var isBound:      Bool { return boundAddress != nil }
  var onClose:      ((CInt) -> Void)? = nil
  
  
  /* initializer / deinitializer */
  
  init(fd: CInt?) {
    self.fd = fd
  }
  deinit {
    close() // TBD: is this OK/safe?
  }
  
  convenience init(type: CInt = SOCK_STREAM) {
    // Generics: let lfd = socket(T.domain, type, 0)
    let lfd = socket(T.domain, type, 0)
    var fd:  CInt?
    if lfd != -1 {
      fd = lfd
    }
    else {
      // This is lame. Would like to 'return nil' ...
      // TBD: How to do proper error handling in Swift?
      println("Could not create socket.")
    }
    
    self.init(fd: fd)
  }
  
  
  /* explicitly close the socket */
  
  func close() {
    if fd {
      let closedFD = fd!
      Darwin.close(fd!)
      fd = nil

      if let cb = onClose {
        // can be used to unregister socket etc when the socket is really closed
        cb(closedFD)
        onClose = nil // break potential cycles
      }
    }
    boundAddress = nil
  }
  
  
  /* bind the socket. */
  
  func bind(address: T) -> Bool {
    if !isValid {
      return false
    }
    if isBound {
      println("Socket is already bound!")
      return false
    }
    
    // Note: must be 'var' for ptr stuff, can't use let
    var addr = address
    
    // CAST: Hope this works, essentially cast to void and then take the rawptr
    let bvptr: CConstVoidPointer = &addr
    let bptr = CConstPointer<sockaddr>(nil, bvptr.value)
    
    // bind!
    let rc = Darwin.bind(fd!, bptr, socklen_t(addr.len));
    
    if rc == 0 {
      // Generics TBD: cannot check for isWildcardPort, always grab the name
      boundAddress = getsockname()
    }
    
    return rc == 0 ? true : false
  }
  
  func getsockname() -> T? {
    if !isValid {
      return nil
    }
    
    // FIXME: tried to encapsulate this in a sockaddrbuf which does all the
    //        ptr handling, but it ain't work (autoreleasepool issue?)
    var baddr    = T()
    var baddrlen = socklen_t(baddr.len)
    
    // CAST: Hope this works, essentially cast to void and then take the rawptr
    let bvptr: CMutableVoidPointer = &baddr
    let bptr = CMutablePointer<sockaddr>(owner: nil, value: bvptr.value)
    
    // Note: we are not interested in the length here, would be relevant
    //       for AF_UNIX sockets
    let buflenptr: CMutablePointer<socklen_t> = &baddrlen
    
    let rc = Darwin.getsockname(fd!, bptr, buflenptr)
    if (rc != 0) {
      return nil
    }
    // println("PORT: \(baddr.sin_port)")
    return baddr
  }
  
  
  /* socket options (TBD: would we use subscripts for such?) */
  
  var reuseAddress: Bool {
    get { return getSocketOption(SO_REUSEADDR) }
    set { setSocketOption(SO_REUSEADDR, value: newValue) }
  }
  var keepAlive: Bool {
    get { return getSocketOption(SO_KEEPALIVE) }
    set { setSocketOption(SO_KEEPALIVE, value: newValue) }
  }
  var dontRoute: Bool {
    get { return getSocketOption(SO_DONTROUTE) }
    set { setSocketOption(SO_DONTROUTE, value: newValue) }
  }
  var socketDebug: Bool {
    get { return getSocketOption(SO_DEBUG) }
    set { setSocketOption(SO_DEBUG, value: newValue) }
  }
  
  var sendBufferSize: CInt {
    get {
      let v: CInt? = getSocketOption(SO_SNDBUF)
      if v { return v! } else { return -42 }
    }
    set { setSocketOption(SO_SNDBUF, value: newValue) }
  }
  var receiveBufferSize: CInt {
    get {
      let v: CInt? = getSocketOption(SO_RCVBUF)
      if v { return v! } else { return -42 }
    }
    set { setSocketOption(SO_RCVBUF, value: newValue) }
  }
  var socketError: CInt {
    let v: CInt? = getSocketOption(SO_ERROR)
    if v { return v! } else { return -42 }
  }
  
  func setSocketOption(option: CInt, value: CInt) -> Bool {
    if !isValid {
      return false
    }
    
    var buf = CInt(value)
    let rc = setsockopt(fd!, SOL_SOCKET, option, &buf, socklen_t(4))
    if rc != 0 { // ps: Great Error Handling
      println("Could not set option \(option) on socket \(self)")
    }
    return rc == 0
  }
  
  // TBD: Can't overload optionals in a useful way?
  // func getSocketOption(option: CInt) -> CInt
  func getSocketOption(option: CInt) -> CInt? {
    if !isValid {
      return nil
    }
    
    var buf    = CInt(0)
    var buflen = socklen_t(sizeof(CInt))
    
    let rc = getsockopt(fd!, SOL_SOCKET, option, &buf, &buflen)
    if rc != 0 { // ps: Great Error Handling
      println("Could not get option \(option) from socket \(self)")
      return nil
    }
    return buf
  }
  
  func setSocketOption(option: CInt, value: Bool) -> Bool {
    return setSocketOption(SO_DONTROUTE, value: value ? 1 : 0)
  }
  func getSocketOption(option: CInt) -> Bool {
    let v: CInt? = getSocketOption(option)
    return v ? (v! == 0 ? false : true) : false
  }
  
  
  // must live in the main-class as 'declarations in extensions cannot be
  // overridden yet'
  func descriptionAttributes() -> String {
    var s = fd ? " fd=\(fd!)" : " closed"
    if boundAddress {
      s += " \(boundAddress!)"
    }
    return s
  }
  
}

/* Swift compiler crashes when I structure the code using extensions w/o
 * protocols (or when I have more than two Extensions per compilation unit?
 *
 * Segfaults swiftc when I move in reuseAddress property.
 * extension Socket { // Socket Options
 * }
 */
extension Socket {
  // can't put socket option methods in here, or the swiftc dies
}


extension Socket: Printable {
  
  var description: String {
    return "<Socket:" + descriptionAttributes() + ">"
  }
  
}


extension Socket: LogicValue {
  
  func getLogicValue() -> Bool {
    return isValid
  }
  
}