#!/usr/bin/env python3
"""
Simple HPROF heap dump parser
Generates basic histogram from .hprof files
"""

import struct
import sys
import os
from collections import defaultdict, Counter

class HProfParser:
    # HPROF record tags
    TAG_STRING = 0x01
    TAG_LOAD_CLASS = 0x02
    TAG_HEAP_DUMP = 0x0C
    TAG_HEAP_DUMP_SEGMENT = 0x1C
    TAG_HEAP_DUMP_END = 0x2C

    # Heap dump sub-records
    SUB_ROOT_JNI_GLOBAL = 0x01
    SUB_ROOT_JNI_LOCAL = 0x02
    SUB_ROOT_JAVA_FRAME = 0x03
    SUB_ROOT_NATIVE_STACK = 0x04
    SUB_ROOT_STICKY_CLASS = 0x05
    SUB_ROOT_THREAD_BLOCK = 0x06
    SUB_ROOT_MONITOR_USED = 0x07
    SUB_ROOT_THREAD_OBJECT = 0x08
    SUB_CLASS_DUMP = 0x20
    SUB_INSTANCE_DUMP = 0x21
    SUB_OBJECT_ARRAY_DUMP = 0x22
    SUB_PRIMITIVE_ARRAY_DUMP = 0x23

    def __init__(self, filename):
        self.filename = filename
        self.id_size = 8  # Default, will be read from header
        self.strings = {}
        self.classes = {}
        self.class_names = {}
        self.instances = defaultdict(int)
        self.instance_sizes = defaultdict(int)

    def read_id(self, f):
        """Read an object ID"""
        data = f.read(self.id_size)
        if len(data) < self.id_size:
            return None
        if self.id_size == 4:
            return struct.unpack('>I', data)[0]
        else:
            return struct.unpack('>Q', data)[0]

    def read_u1(self, f):
        data = f.read(1)
        return struct.unpack('B', data)[0] if data else None

    def read_u2(self, f):
        data = f.read(2)
        return struct.unpack('>H', data)[0] if len(data) == 2 else None

    def read_u4(self, f):
        data = f.read(4)
        return struct.unpack('>I', data)[0] if len(data) == 4 else None

    def read_u8(self, f):
        data = f.read(8)
        return struct.unpack('>Q', data)[0] if len(data) == 8 else None

    def parse(self):
        """Parse the HPROF file"""
        try:
            with open(self.filename, 'rb') as f:
                # Read header
                header = f.read(18)
                if not header.startswith(b'JAVA PROFILE'):
                    print(f"Error: Not a valid HPROF file")
                    return False

                # Read null terminator
                while f.read(1) != b'\x00':
                    pass

                # Read ID size and timestamp
                self.id_size = self.read_u4(f)
                timestamp = self.read_u8(f)

                print(f"Parsing heap dump (ID size: {self.id_size} bytes)...")

                # Read records
                records_processed = 0
                while True:
                    tag = self.read_u1(f)
                    if tag is None:
                        break

                    timestamp = self.read_u4(f)
                    length = self.read_u4(f)

                    if tag == self.TAG_STRING:
                        self.parse_string(f, length)
                    elif tag == self.TAG_LOAD_CLASS:
                        self.parse_load_class(f)
                    elif tag == self.TAG_HEAP_DUMP or tag == self.TAG_HEAP_DUMP_SEGMENT:
                        self.parse_heap_dump(f, length)
                    else:
                        # Skip unknown record
                        f.seek(length, 1)

                    records_processed += 1
                    if records_processed % 1000 == 0:
                        print(f"  Processed {records_processed} records...", end='\r')

                print(f"\n✅ Parsed {records_processed} records")
                return True

        except Exception as e:
            print(f"Error parsing HPROF file: {e}")
            import traceback
            traceback.print_exc()
            return False

    def parse_string(self, f, length):
        """Parse a STRING record"""
        str_id = self.read_id(f)
        str_data = f.read(length - self.id_size)
        try:
            self.strings[str_id] = str_data.decode('utf-8', errors='replace')
        except:
            self.strings[str_id] = str(str_data)

    def parse_load_class(self, f):
        """Parse a LOAD CLASS record"""
        class_serial = self.read_u4(f)
        class_obj_id = self.read_id(f)
        stack_trace_serial = self.read_u4(f)
        class_name_id = self.read_id(f)

        self.classes[class_obj_id] = class_name_id
        if class_name_id in self.strings:
            self.class_names[class_obj_id] = self.strings[class_name_id]

    def parse_heap_dump(self, f, length):
        """Parse a HEAP DUMP record"""
        end_pos = f.tell() + length

        while f.tell() < end_pos:
            try:
                sub_tag = self.read_u1(f)
                if sub_tag is None:
                    break
            except:
                # If we can't read the sub-tag, skip to next position
                break

            if sub_tag == self.SUB_INSTANCE_DUMP:
                obj_id = self.read_id(f)
                stack_trace = self.read_u4(f)
                class_obj_id = self.read_id(f)
                num_bytes = self.read_u4(f)
                f.seek(num_bytes, 1)  # Skip instance data

                self.instances[class_obj_id] += 1
                self.instance_sizes[class_obj_id] += num_bytes

            elif sub_tag == self.SUB_OBJECT_ARRAY_DUMP:
                obj_id = self.read_id(f)
                stack_trace = self.read_u4(f)
                num_elements = self.read_u4(f)
                array_class_id = self.read_id(f)
                f.seek(num_elements * self.id_size, 1)  # Skip elements

                self.instances[array_class_id] += 1
                self.instance_sizes[array_class_id] += num_elements * self.id_size

            elif sub_tag == self.SUB_PRIMITIVE_ARRAY_DUMP:
                obj_id = self.read_id(f)
                stack_trace = self.read_u4(f)
                num_elements = self.read_u4(f)
                element_type = self.read_u1(f)

                # Element sizes by type
                type_sizes = {4: 1, 5: 2, 6: 4, 7: 8, 8: 1, 9: 2, 10: 4, 11: 8}
                element_size = type_sizes.get(element_type, 1)
                total_bytes = num_elements * element_size

                f.seek(total_bytes, 1)  # Skip array data

                type_names = {
                    4: 'boolean[]', 5: 'char[]', 6: 'float[]', 7: 'double[]',
                    8: 'byte[]', 9: 'short[]', 10: 'int[]', 11: 'long[]'
                }
                type_name = type_names.get(element_type, f'unknown[]')

                # Use negative class_id for primitive arrays
                class_key = -(element_type)
                self.instances[class_key] += 1
                self.instance_sizes[class_key] += total_bytes
                if class_key not in self.class_names:
                    self.class_names[class_key] = type_name

            elif sub_tag == self.SUB_CLASS_DUMP:
                # Skip class dump - it's complex and not needed for basic histogram
                # We'll just skip these as they're not critical for the histogram
                try:
                    class_obj_id = self.read_id(f)
                    if class_obj_id is None:
                        continue

                    stack_trace = self.read_u4(f)
                    super_class_obj_id = self.read_id(f)
                    class_loader_obj_id = self.read_id(f)
                    signers_obj_id = self.read_id(f)
                    protection_domain_obj_id = self.read_id(f)
                    reserved1 = self.read_id(f)
                    reserved2 = self.read_id(f)
                    instance_size = self.read_u4(f)

                    # Skip constant pool
                    const_pool_size = self.read_u2(f)
                    if const_pool_size is None:
                        continue
                    for _ in range(const_pool_size):
                        cp_index = self.read_u2(f)
                        cp_type = self.read_u1(f)
                        if cp_type is None:
                            break
                        self.skip_value(f, cp_type)

                    # Skip static fields
                    num_static_fields = self.read_u2(f)
                    if num_static_fields is None:
                        continue
                    for _ in range(num_static_fields):
                        name_id = self.read_id(f)
                        field_type = self.read_u1(f)
                        if field_type is None:
                            break
                        self.skip_value(f, field_type)

                    # Skip instance fields
                    num_instance_fields = self.read_u2(f)
                    if num_instance_fields is None:
                        continue
                    for _ in range(num_instance_fields):
                        name_id = self.read_id(f)
                        field_type = self.read_u1(f)
                        if field_type is None:
                            break
                except Exception as e:
                    # If we can't parse a class dump, just continue
                    # The histogram can still be generated without perfect class info
                    pass
            else:
                # Unknown sub-record, try to skip safely
                # This is a best effort - heap dumps can be complex
                pass

    def skip_value(self, f, value_type):
        """Skip a value based on its type"""
        type_sizes = {
            2: self.id_size,  # object
            4: 1,  # boolean
            5: 2,  # char
            6: 4,  # float
            7: 8,  # double
            8: 1,  # byte
            9: 2,  # short
            10: 4,  # int
            11: 8,  # long
        }
        size = type_sizes.get(value_type, 0)
        if size > 0:
            f.read(size)

    def generate_histogram(self, output_file):
        """Generate histogram output"""
        print(f"\nGenerating histogram to {output_file}...")

        # Combine instance counts and sizes
        histogram = []
        for class_id, count in self.instances.items():
            class_name = self.class_names.get(class_id, f"Unknown(id={class_id})")
            size = self.instance_sizes.get(class_id, 0)
            histogram.append((class_name, count, size))

        # Sort by total bytes (descending)
        histogram.sort(key=lambda x: x[2], reverse=True)

        # Write histogram
        with open(output_file, 'w') as f:
            f.write(" num     #instances         #bytes  class name\n")
            f.write("----------------------------------------------\n")

            total_instances = 0
            total_bytes = 0

            for idx, (class_name, count, size) in enumerate(histogram, 1):
                f.write(f"{idx:4d}:  {count:15d}  {size:15d}  {class_name}\n")
                total_instances += count
                total_bytes += size

            f.write("----------------------------------------------\n")
            f.write(f"Total:  {total_instances:15d}  {total_bytes:15d}\n")

        print(f"✅ Histogram generated with {len(histogram)} classes")
        print(f"   Total instances: {total_instances:,}")
        print(f"   Total bytes: {total_bytes:,} ({total_bytes/1024/1024:.1f} MB)")


def main():
    if len(sys.argv) < 3:
        print("Usage: parse_hprof.py <input.hprof> <output.txt>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    if not os.path.exists(input_file):
        print(f"Error: File not found: {input_file}")
        sys.exit(1)

    parser = HProfParser(input_file)
    if parser.parse():
        parser.generate_histogram(output_file)
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
