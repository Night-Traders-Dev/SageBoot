## Minimal freestanding FAT12/FAT16/FAT32 reader in SageLang
import hardware as hw

@inline
proc read_u16(bs, off) -> Int:
    return mem_read(bs + off, 0, "byte") + mem_read(bs + off + 1, 0, "byte") * 256

@inline
proc read_u32(bs, off) -> Int:
    let l1 = mem_read(bs + off, 0, "byte")
    let l2 = mem_read(bs + off + 1, 0, "byte") * 256
    let h1 = mem_read(bs + off + 2, 0, "byte") * 65536
    let h2 = mem_read(bs + off + 3, 0, "byte") * 16777216
    return l1 + l2 + h1 + h2

proc parse_fat_bpb(img_ptr) -> Map:
    let sector_size = read_u16(img_ptr, 11)
    if sector_size == 0:
        return nil
    let sectors_per_cluster = mem_read(img_ptr + 13, 0, "byte")
    let reserved_sectors = read_u16(img_ptr, 14)
    let num_fats = mem_read(img_ptr + 16, 0, "byte")
    let root_entry_count = read_u16(img_ptr, 17)
    let total_sectors_16 = read_u16(img_ptr, 19)
    let fat_size_16 = read_u16(img_ptr, 22)
    
    let total_sectors = total_sectors_16
    if total_sectors == 0:
        total_sectors = read_u32(img_ptr, 32)
        
    let fat_size = fat_size_16
    if fat_size == 0:
        fat_size = read_u32(img_ptr, 36)
        
    let root_dir_sectors = (((root_entry_count * 32) + (sector_size - 1)) / sector_size) | 0
    let first_data_sector = reserved_sectors + (num_fats * fat_size) + root_dir_sectors
    
    let data_sectors = total_sectors - first_data_sector
    let total_clusters = (data_sectors / sectors_per_cluster) | 0
    
    let fat_type = "FAT16"
    if total_clusters < 4085:
        fat_type = "FAT12"
    elif total_clusters < 65525:
        fat_type = "FAT16"
    else:
        fat_type = "FAT32"
        
    let root_cluster = 0
    if fat_type == "FAT32":
        root_cluster = read_u32(img_ptr, 44)
        
    let vol = {}
    vol["img_ptr"] = img_ptr
    vol["sector_size"] = sector_size
    vol["sectors_per_cluster"] = sectors_per_cluster
    vol["reserved_sectors"] = reserved_sectors
    vol["num_fats"] = num_fats
    vol["fat_size"] = fat_size
    vol["root_entry_count"] = root_entry_count
    vol["first_data_sector"] = first_data_sector
    vol["fat_type"] = fat_type
    vol["root_cluster"] = root_cluster
    vol["root_dir_sectors"] = root_dir_sectors
    return vol

# Locate file metadata inside the FAT filesystem
proc find_fat_file(vol, filename: String) -> Map:
    let img_ptr = vol["img_ptr"]
    let sector_size = vol["sector_size"]
    
    # Locate Root Directory LBA
    let root_dir_lba = vol["reserved_sectors"] + vol["num_fats"] * vol["fat_size"]
    let root_dir_size_bytes = vol["root_entry_count"] * 32
    
    let entries_checked = 0
    while entries_checked < vol["root_entry_count"]:
        let entry_offset = root_dir_lba * sector_size + (entries_checked * 32)
        let entry_ptr = img_ptr + entry_offset
        
        # Check first byte of name
        let first_char = mem_read(entry_ptr, 0, "byte")
        if first_char == 0:
            return nil # End of directory
        if first_char == 229:
            # Deleted file
            entries_checked = entries_checked + 1
            continue
            
        let attr = mem_read(entry_ptr, 11, "byte")
        if attr == 15: # Long File Name attribute
            entries_checked = entries_checked + 1
            continue
            
        # Parse standard 8.3 filename
        let s = ""
        let n = 0
        while n < 8:
            let c = mem_read(entry_ptr, n, "byte")
            if c != 32:
                s = s + chr(c)
            n = n + 1
            
        let ext = ""
        n = 0
        while n < 3:
            let c = mem_read(entry_ptr, 8 + n, "byte")
            if c != 32:
                ext = ext + chr(c)
            n = n + 1
            
        if len(ext) > 0:
            s = s + "." + ext
            
        # Match filenames (case insensitive standard check)
        if upper(s) == upper(filename):
            let first_cluster_hi = read_u16(entry_ptr, 20)
            let first_cluster_lo = read_u16(entry_ptr, 26)
            let cluster = first_cluster_lo + first_cluster_hi * 65536
            let size = read_u32(entry_ptr, 28)
            
            let res = {}
            res["cluster"] = cluster
            res["size"] = size
            return res
            
        entries_checked = entries_checked + 1
        
    return nil

# Reads a file cluster sequence into a newly allocated buffer
proc load_fat_file(vol, file_info) -> Int:
    let img_ptr = vol["img_ptr"]
    let sector_size = vol["sector_size"]
    let sectors_per_cluster = vol["sectors_per_cluster"]
    let cluster_size = sector_size * sectors_per_cluster
    
    let size = file_info["size"]
    let start_cluster = file_info["cluster"]
    
    # Allocate a buffer to copy file contents
    let buf = mem_alloc(size)
    if buf == nil:
        return 0
        
    let current_cluster = start_cluster
    let bytes_read = 0
    
    while current_cluster >= 2 and current_cluster < 0xFFF0:
        # Calculate cluster LBA
        let lba = vol["first_data_sector"] + (current_cluster - 2) * sectors_per_cluster
        let cluster_ptr = img_ptr + (lba * sector_size)
        
        let chunk_size = cluster_size
        if size - bytes_read < chunk_size:
            chunk_size = size - bytes_read
            
        # Copy chunk bytes
        let b = 0
        while b < chunk_size:
            let val = mem_read(cluster_ptr + b, 0, "byte")
            mem_write(buf, bytes_read, "byte", val)
            bytes_read = bytes_read + 1
            b = b + 1
            
        if bytes_read >= size:
            break
            
        # Read next cluster from FAT table
        let fat_lba = vol["reserved_sectors"]
        let fat_offset = 0
        if vol["fat_type"] == "FAT16":
            fat_offset = current_cluster * 2
            current_cluster = read_u16(img_ptr + (fat_lba * sector_size), fat_offset)
        elif vol["fat_type"] == "FAT32":
            fat_offset = current_cluster * 4
            current_cluster = read_u32(img_ptr + (fat_lba * sector_size), fat_offset) & 0x0FFFFFFF
        else: # FAT12
            # Minimal FAT12 table parse
            fat_offset = (current_cluster + (current_cluster >> 1)) | 0
            let raw_val = read_u16(img_ptr + (fat_lba * sector_size), fat_offset)
            if (current_cluster & 1) != 0:
                current_cluster = raw_val >> 4
            else:
                current_cluster = raw_val & 0x0FFF
                
    return buf
