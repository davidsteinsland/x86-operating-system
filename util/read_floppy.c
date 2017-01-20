#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef signed char int8_t;
typedef unsigned char uint8_t;

typedef signed short int16_t;
typedef unsigned short uint16_t;

typedef signed int int32_t;
typedef unsigned int uint32_t;

/*

 */

typedef struct {
	/* BPB 2.0 */
	uint16_t bytes_per_logical_sector;
	uint8_t logical_sectors_per_cluster;
	uint16_t reserved_logical_sectors;
	uint8_t number_of_fats;
	uint16_t root_directory_entries;
	uint16_t total_logical_sectors;
	uint8_t media_descriptor;
	uint16_t logical_sectors_per_fat;
	/* End BPB 2.0 */

	/* BPB 3.31 */
	uint16_t physical_sectors_per_track;
	uint16_t heads_per_cylinder;
	uint32_t hidden_sectors_count;
	uint32_t total_logical_sectors_including_hidden;
	/* End BPB 3.31 */

	/* EBPB - Extended BIOS Parameter Block */
	uint8_t drive_number;
	uint8_t reserved;

	uint8_t extended_boot_signature; /* should be 0x29 */
	uint8_t volume_id[4];
	uint8_t partition_volume_label[11];
	uint8_t filesystem_type[8];
} __attribute__((packed)) bpb_t;

typedef struct {
	uint8_t jmp; /* jmp instruction */
	uint8_t jmp_target; /* target of jmp instruction */
	uint8_t nop; /* the nop instruction */

	uint8_t oem[8]; /* oem name, 8 bytes */
} __attribute__((packed)) fat_header_t;

typedef struct {
	uint8_t filename[8];
	uint8_t ext[3];
	uint8_t attr;
	uint8_t reserved1;
	uint8_t creation_ts;
	uint16_t creation_time;
	uint16_t creation_date;
	uint16_t last_access_date;
	uint16_t reserved2;
	uint16_t last_modified_time;
	uint16_t last_modified_date;
	uint16_t cluster;
	uint32_t filesize;
} __attribute__((packed)) dir_entry_t;

static void output_chars(char* buf, uint8_t len) {
	uint8_t k;
	for (k = 0; k < len; k++) {
		printf("%c", buf[k]);
	}
}

static void output_attribute(uint8_t attr) {
	if (attr & 0x01) {
		printf("Read only ");
	}

	if (attr & 0x02) {
		printf("Hidden ");
	}

	if (attr & 0x04) {
		printf("System ");
	}

	if (attr & 0x08) {
		printf("Volume label ");
	}

	if (attr & 0x10) {
		printf("Subdir ");
	}

	if (attr & 0x20) {
		printf("Archive ");
	}

	if (attr & 0x40) {
		printf("Device ");
	}

	if (attr & 0x80) {
		printf("Reserved");
	}
}

static void output_time(uint16_t time) {
	/*
		bits    description
		15-11 	Hours (0-23)
		10-5 	Minutes (0-59)
		4-0 	Seconds/2 (0-29)
	 */
	uint8_t hours = time >> 0xB;
	uint8_t minutes = (time >> 0x5) & 0x6;
	uint8_t seconds = time & 0x5;

	printf("%02d:%02d:%02d", hours, minutes, seconds);
}

static void output_date(uint16_t date) {
	/*
		bits    description
		15-9 	Year (0 = 1980, 119 = 2099 supported under DOS/Windows, theoretically up to 127 = 2107)
		8-5 	Month (1–12)
		4-0 	Day (1–31)

		[- - - - - - -] [- - - -] [- - - - -]
	 */
	uint16_t year = 1980 + (date >> 0x9);
	uint8_t month = (date >> 0x5) & 0x4;
	uint8_t day = date & 0x5;

	printf("%02d.%02d.%d", day, month, year);
}

/* decode the FAT table into the 12 bit entries it should be */
void decode_fat(FILE* fp, bpb_t* bpb) {
	uint16_t fat_table_offset = bpb->reserved_logical_sectors + bpb->hidden_sectors_count;
	uint16_t fat_table_offset_in_bytes = fat_table_offset * bpb->bytes_per_logical_sector;

	/* read the whole FAT into memory. Each FAT consists of
		bpb->logical_sectors_per_fat sectors
		the FAT entries occupy 12 bits each */
	if (fseek(fp, fat_table_offset_in_bytes, SEEK_SET)) {
		fprintf(stderr, "Could not seek to position %d\n", fat_table_offset_in_bytes);
		exit(EXIT_FAILURE);
	}

	uint16_t fat_size = bpb->bytes_per_logical_sector * bpb->logical_sectors_per_fat;
	uint16_t k;
	uint8_t buf[fat_size];

	for (k = 0; k < fat_size; k++) {
		buf[k] = fgetc(fp);
	}

	uint16_t fat_table[fat_size/3];
	uint16_t i = 0;

	for (k = 0; k < fat_size/3; k++) {
		/* three bytes = 2 FAT entries */
		uint16_t offset = 3 * k;

		uint8_t b1 = buf[offset + 0];
		uint8_t b2 = buf[offset + 1];
		uint8_t b3 = buf[offset + 2];

		/*
			b1: bc   =  1011 1100
			b2: fa   =  1111 1010
			b3: de   =  1101 1110

			because of little endian,
			"bc" is the LSB in the first entry
			"f" is the LSB in the second entry
			"a" is the MSB in the first entry
			"de" is the MSB in the second entry

			entry1 = ((b2 & 0xF) << 8) | b1;
			entry2 = (b3 << 4) | (b2 >> 4)
		 */

		uint16_t e1 = ((b2 & 0xF) << 8) | b1;
		uint16_t e2 = (b3 << 4) | (b2 >> 4);

		fat_table[i++] = e1;
		fat_table[i++] = e2;
	}
}

#define SECTOR_SIZE 512
#define FAT_ENTRY_SIZE 32

int main(int argc, char** argv) {

	if (argc != 2) {
		fprintf(stderr, "Usage: %s INPUT_FILE\n", argv[0]);
		return EXIT_FAILURE;
	}

	FILE* fp;
	fp = fopen(argv[1], "rb");

	if (!fp) {
		fprintf(stderr, "Failed to open file for reading\n");
		return EXIT_FAILURE;
	}

	printf("Size of FAT header: %lu bytes\n", sizeof(fat_header_t));
	printf("Size of BPB header: %lu bytes\n", sizeof(bpb_t));
	printf("Size of DIR header: %lu bytes\n", sizeof(dir_entry_t));

	uint8_t buf[SECTOR_SIZE];
	uint16_t k;
	for (k = 0; k < SECTOR_SIZE; k++) {
		buf[k] = fgetc(fp);
	}

	fat_header_t* header;
	header = (fat_header_t*)&buf;

	bpb_t* bpb;
	bpb = (bpb_t*)&buf[sizeof(fat_header_t)];

	printf("OEM: <");
	output_chars((char*)&header->oem, 8);
	printf(">\n");

	printf("Bytes per logical sector: %d\n", bpb->bytes_per_logical_sector);
	printf("Logical sectors per cluster: %d\n", bpb->logical_sectors_per_cluster);
	printf("Reserved logical sectors: %d\n", bpb->reserved_logical_sectors);
	printf("Number of FATs: %d\n", bpb->number_of_fats);
	printf("Root directory entries: %d\n", bpb->root_directory_entries);
	printf("Total logical sectors: %d\n", bpb->total_logical_sectors);
	printf("Total logical sectors: 0x%x\n", bpb->total_logical_sectors);
	printf("Media descriptor: 0x%x\n", bpb->media_descriptor);
	printf("Logical sectors per FAT: %d\n", bpb->logical_sectors_per_fat);
	printf("Physical sectors per track: %d\n", bpb->physical_sectors_per_track);
	printf("Heads per cylinder: %d\n", bpb->heads_per_cylinder);
	printf("Hidden sectors count: %d\n", bpb->hidden_sectors_count);
	printf("Total logical sectors including hidden: %d\n", bpb->total_logical_sectors_including_hidden);

	printf("Drive number: %d\n", bpb->drive_number);
	printf("Boot signature number: 0x%x\n", bpb->extended_boot_signature);


	printf("Volume label: <");
	output_chars((char*)&bpb->partition_volume_label, 11);
	printf(">\n");

	printf("Filesystem type: <");
	output_chars((char*)&bpb->filesystem_type, 8);
	printf(">\n");

	printf("\n");
	printf("Output of first sector:\n");
	for (k = 0; k < SECTOR_SIZE; k++) {
		printf("%02x ", buf[k]);

		if ((k + 1) % 16 == 0) {
			printf("\n");
		}
	}
	printf("\n");

	uint16_t root_dir_size = (FAT_ENTRY_SIZE * bpb->root_directory_entries) / bpb->bytes_per_logical_sector;
	printf("Root directory size: %d sectors\n", root_dir_size);
	printf("Root directory size: %d bytes\n", FAT_ENTRY_SIZE * bpb->root_directory_entries);

	uint16_t root_dir_offset = bpb->number_of_fats * bpb->logical_sectors_per_fat
		+ bpb->hidden_sectors_count + bpb->reserved_logical_sectors;
	uint16_t root_dir_offset_in_bytes = root_dir_offset * bpb->bytes_per_logical_sector;

	printf("Root directory offset: %d\n", root_dir_offset);
	printf("Root directory offset: %d * %d = %d bytes\n", root_dir_offset, bpb->bytes_per_logical_sector,
		root_dir_offset_in_bytes);

	uint16_t fat_table_offset = bpb->reserved_logical_sectors + bpb->hidden_sectors_count;
	uint16_t fat_table_offset_in_bytes = fat_table_offset * bpb->bytes_per_logical_sector;
	printf("Offset of FAT table: %d sectors\n", fat_table_offset);
	printf("Offset of FAT table: %d bytes\n", fat_table_offset_in_bytes);

	printf("First data sector: %d\n", root_dir_size + root_dir_offset);

	decode_fat(fp, bpb);

	/* read the whole FAT into memory. Each FAT consists of
		bpb->logical_sectors_per_fat sectors
		the FAT entries occupy 12 bits each */
	if (fseek(fp, fat_table_offset_in_bytes, SEEK_SET)) {
		fprintf(stderr, "Could not seek to position %d\n", fat_table_offset_in_bytes);
		return EXIT_FAILURE;
	}
	uint8_t fatbuf[bpb->bytes_per_logical_sector * bpb->logical_sectors_per_fat];
	for (k = 0; k < bpb->bytes_per_logical_sector * bpb->logical_sectors_per_fat; k++) {
		fatbuf[k] = fgetc(fp);
	}

	printf("\n");
	printf("Output of FAT table (only first sector):\n");
	for (k = 0; k < bpb->bytes_per_logical_sector; k++) {
		printf("%02x ", fatbuf[k]);

		if ((k + 1) % 16 == 0) {
			printf("\n");
		}
	}
	printf("\n");

	if (fseek(fp, root_dir_offset_in_bytes, SEEK_SET)) {
		fprintf(stderr, "Could not seek to position %d\n", root_dir_offset_in_bytes);
		return EXIT_FAILURE;
	}

	uint16_t p;
	/* read all root directory sectors, one at a time */
	for (p = 0; p < root_dir_size; p++) {
		/* read one root directory into memory */
		uint8_t dirbuf[bpb->bytes_per_logical_sector];

		for (k = 0; k < bpb->bytes_per_logical_sector; k++) {
			dirbuf[k] = fgetc(fp);
		}

		/* we just care about the first sector, because this is an example .. */
		if (p == 0) {
			/* each directory entry is 32 bytes, which makes
				bpb->bytes_per_logical_sector / 32 entries per sector */
			uint16_t entries_per_sector = bpb->bytes_per_logical_sector / FAT_ENTRY_SIZE;
			dir_entry_t* entries = (dir_entry_t*)&dirbuf[0];

			for (k = 0; k < entries_per_sector; k++) {
				printf("Filename: ");
				output_chars(entries[k].filename, 8);
				printf(" --> ");
				printf("Attribute: 0x%02x: ", entries[k].attr);
				output_attribute(entries[k].attr);
				printf(" --> Cluster: %d\n", entries[k].cluster);
				printf("\n");
			}

			/* loop thru every entry in the directory */
			for (k = 0; k < entries_per_sector; k++) {
				dir_entry_t* entry = &entries[k];

				/* look for a special file */
				char* my_file = "SECOND  ";
				uint8_t ok = 1;
				uint8_t pos = 0;
				/* a filename can only be 8 bytes */
				for (pos = 0; pos < 8; pos++) {
					if (my_file[pos] != entry->filename[pos]) {
						ok = 0;
						break;
					}
				}

				if (ok == 0) {
					/* test for the directory */
					my_file = "TESTDIR ";
					ok = 1;
					/* a filename can only be 8 bytes */
					for (pos = 0; pos < 8; pos++) {
						if (my_file[pos] != entry->filename[pos]) {
							ok = 0;
							break;
						}
					}


					if (ok == 0) {
						continue;
					}
				}

				printf("Dir Entry %d\n", k / FAT_ENTRY_SIZE);
				printf("Filename: <");
				output_chars(entry->filename, 8);
				printf(">\n");
				printf("Extension: <");
				output_chars(entry->ext, 3);
				printf(">\n");
				printf("Attribute: 0x%02x: ", entry->attr);
				output_attribute(entry->attr);
				printf("\n");
				printf("Create time: ");
				output_time(entry->creation_time);
				printf("\n");
				printf("Create date: ");
				output_date(entry->creation_date);
				printf("\n");
				printf("Cluster: %d\n", entry->cluster);
				printf("Filesize: %d bytes\n", entry->filesize);

				/*
					the fat table has one entry per cluster
					The FAT12 file system uses 12 bits per FAT entry, thus two entries span 3 bytes.
					The first cluster of the data area is cluster #2.
					That leaves the first two entries of the FAT unused.
					In the first byte of the first entry a copy of the media descriptor is stored.
				 */
				uint16_t cluster = entry->cluster;
				uint32_t remaining_size = entry->filesize;

				while (1) {
					/* subtract two because first two entries in FAT is reserved */
					uint16_t file_sector = ((cluster - 2) * bpb->logical_sectors_per_cluster) + root_dir_size + root_dir_offset;
					uint16_t file_sector_offset = file_sector * bpb->bytes_per_logical_sector;
					uint16_t read_size = bpb->bytes_per_logical_sector;

					if (remaining_size < bpb->bytes_per_logical_sector) {
						read_size = remaining_size;
					}

					if (fseek(fp, file_sector_offset, SEEK_SET)) {
						fprintf(stderr, "Could not seek to position %d\n", file_sector_offset);
						return EXIT_FAILURE;
					}

					if (read_size > 0) {
						uint16_t o;
						for (o = 0; o < read_size; o++) {
							printf("%c", fgetc(fp));
						}
					} else {
						/* Subdirectories have a filesize entry of zero. */
						if (entry->filesize == 0) {
							printf("Its a directory, the contents of the cluster is a directory entry\n");

							/* read the 512 byte sector size */
							uint8_t subdirbuf[bpb->bytes_per_logical_sector];

							uint16_t o;
							for (o = 0; o < bpb->bytes_per_logical_sector; o++) {
								subdirbuf[o] = fgetc(fp);
							}

							dir_entry_t* subdirentries = (dir_entry_t*)&subdirbuf[0];

							for (o = 0; o < bpb->bytes_per_logical_sector/FAT_ENTRY_SIZE; o++) {
								printf("Filename: ");
								output_chars(subdirentries[o].filename, 8);
								printf(" --> ");
								printf("Attribute: 0x%02x: ", subdirentries[o].attr);
								output_attribute(subdirentries[o].attr);
								printf(" --> Cluster: %d\n", subdirentries[o].cluster);
								printf("\n");
							}
						}
					}

					printf("Reading %d bytes in sector %d (offset 0x%04x)\n", read_size, file_sector, file_sector_offset);
					remaining_size = remaining_size - read_size;

					uint16_t fat_offset = cluster + cluster/2;
					uint16_t fat_value = *(uint16_t*)&fatbuf[fat_offset];

					printf("FAT offset: %d\n", fat_offset);
					printf("Value at this offset: 0x%04x\n", fat_value);

					if (cluster & 1) {
						/* odd value, shift off 4 last bits */
						cluster = fat_value >> 4;
					} else {
						/* even value, mask out upper 4 bits */
						cluster = fat_value & 0xFFF;
					}

					if (cluster >= 0xFF8) {
						printf("No more entries\n");
						break;
					} else if (cluster == 0xFF7) {
						printf("Entry marked as bad\n");
						break;
					} else {
						printf("Next cluster: %d\n", cluster);
					}
				}

				//break;
			}

			printf("\nOutput of first root dir sector:\n");
			for (k = 0; k < bpb->bytes_per_logical_sector; k++) {
				printf("%02x ", dirbuf[k]);

				if ((k + 1) % 16 == 0) {
					printf("  |  ");
					uint8_t q;
					for (q = 0; q < 16; q++) {
						uint8_t m = dirbuf[k - 15 + q];

						if ((m >= 'a' && m <= 'z') || (m >= 'A' && m <= 'Z') || (m >= '0' && m <= '9')) {
							printf("%c", m);
						} else {
							printf(".");
						}
					}

					printf("\n");
				}
			}
			printf("\n");
		}
	}

	fclose(fp);

	return EXIT_SUCCESS;
}
