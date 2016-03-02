//===--- ExpressMarkdown.swift -------------------------------------------===//
//
//Copyright (c) 2016 Daniel Leping (dileping)
//
//This file is part of Swift Express.
//
//Swift Express is free software: you can redistribute it and/or modify
//it under the terms of the GNU Lesser General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.
//
//Swift Express is distributed in the hope that it will be useful,
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU Lesser General Public License for more details.
//
//You should have received a copy of the GNU Lesser General Public License
//along with Swift Express.  If not, see <http://www.gnu.org/licenses/>.
//
//===----------------------------------------------------------------------===//

import Foundation
import Express
import Markdown
import BrightFutures

public struct MarkdownPageConfig {
    let view:String
    let param:String
    let options:Options
}

public class MarkdownDataProvider : StaticDataProviderType {
    let root:String
    let ext:String
    let fm = NSFileManager.defaultManager()
    let single:MarkdownPageConfig?
    let multi:MarkdownPageConfig?
    
    public init(root:String, ext:String = "md", single:MarkdownPageConfig?, multi:MarkdownPageConfig?) {
        self.root = root
        self.ext = ext
        self.single = single
        self.multi = multi
    }
    
    func fullPath(file:String) -> String {
        return root.bridge().stringByAppendingPathComponent(file)
    }
    
    public func etag(path:String) -> Future<String, AnyError> {
        let file = fullPath(path)
        
        return future {
            let attributes = try self.fm.attributesOfItemAtPath(file)
            
            guard let modificationDate = (attributes[NSFileModificationDate].flatMap{$0 as? NSDate}) else {
                //TODO: throw different error
                throw ExpressError.PageNotFound(path: path)
            }
            
            let timestamp = UInt64(modificationDate.timeIntervalSince1970 * 1000 * 1000)
            
            //TODO: use MD5 of fileFromURI + timestamp
            let etag = "\"" + String(timestamp) + "\""
            
            return etag
        }
    }
    
    func processMarkdown(file:String, options:Options) throws -> [String: Any] {
        //TODO: get rid of NS
        guard let data = NSData(contentsOfFile: file) else {
            throw ExpressError.FileNotFound(filename: file)
        }
        
        let count = data.length / sizeof(UInt8)
        // create array of appropriate length:
        var array = [CChar](count: count, repeatedValue: 0)
        
        // copy bytes into array
        data.getBytes(&array, length:count * sizeof(UInt8))
        
        guard let string = String.fromCString(&array) else {
            throw ExpressError.FileNotFound(filename: file)
        }
        
        let markdown = try Markdown(string: string)
        
        var result = [String: Any]()
        
        if let title = markdown.title {
            result.updateValue(title, forKey: "title")
        }
        
        if let author = markdown.author {
            result.updateValue(author, forKey: "author")
        }
        
        if let date = markdown.date {
            result.updateValue(date, forKey: "date")
        }
        
        let document = try markdown.document()
        result.updateValue(document, forKey: "document")
        
        let toc = try markdown.tableOfContents()
        result.updateValue(toc, forKey: "toc")
        
        let css = try markdown.css()
        result.updateValue(css, forKey: "css")
        
        return result
    }
    
    func contextForFileOrDir(path:String) throws -> (MarkdownPageConfig, [String: Any]) {
        let file = fullPath(path)
        
        var isDir = ObjCBool(false)
        if fm.fileExistsAtPath(file, isDirectory: &isDir) && isDir.boolValue {
            guard let multi = self.multi else {
                throw ExpressError.PageNotFound(path: path)
            }
            let files = try fm.contentsOfDirectoryAtPath(file)
            let processed = try files.map { file in
                try processMarkdown(file, options: multi.options)
            }
            return (multi, [multi.param: processed])
        } else {
            guard let single = self.single else {
                throw ExpressError.PageNotFound(path: path)
            }
            guard let filename = file.bridge().stringByAppendingPathExtension(ext) else {
                throw ExpressError.PageNotFound(path: path)
            }
            let markdown = try processMarkdown(filename, options: single.options)
            return (single, [single.param: markdown])
        }
    }
    
    public func data(app:Express, file:String) -> Future<FlushableContentType, AnyError> {
        return future {
            try self.contextForFileOrDir(file)
        }.flatMap { (config, context) in
            app.views.render(config.view, context: context)
        }
    }
}

public class MarkdownAction : BaseStaticAction<AnyContent> {
    
    public init(path:String, param:String, ext:String = "md", single:MarkdownPageConfig?, multi:MarkdownPageConfig?, cacheControl:CacheControl = .NoCache) {
        let dataProvider = MarkdownDataProvider(root: path, ext: ext, single: single, multi: multi)
        super.init(param: param, dataProvider: dataProvider, cacheControl: cacheControl)
    }
    
}