import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.text.DateFormat;
import java.util.Date;
import java.text.SimpleDateFormat;

// javac -classpath /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/ojdbc6.jar Metadata.java
// java -classpath "/usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/ojdbc6.jar:." Metadata

/**
 * @author Andres.Cespedes
 * @version 1.0 $Date: 24/01/2015
 * @since 1.7
 */
public class Metadata {

	static Connection connection = null;
	static DatabaseMetaData metadata = null;

	private static String DB_URL = "jdbc:oracle:thin:@oracle:1521/XE";
	private static String DB_USER = "myuser";
	private static String DB_PASSWORD = "mypassword";

	private static Connection getConnection() throws SQLException {
		Connection connection = DriverManager.getConnection(DB_URL, DB_USER,
				DB_PASSWORD);
		System.err.println("The connection is successfully obtained");
		return connection;
	}

	// Static block for initialization
	static {
		try {
			connection = Metadata.getConnection();
		} catch (SQLException e) {
			System.err.println("There was an error getting the connection: "
					+ e.getMessage());
		}

		try {
			metadata = connection.getMetaData();
		} catch (SQLException e) {
			System.err.println("There was an error getting the metadata: "
					+ e.getMessage());
		}
	}

	/**
	 * Prints in the console the general metadata.
	 *
	 * @throws SQLException
	 */
	public static void printGeneralMetadata() throws SQLException {
		System.out.println("Database Product Name: "
				+ metadata.getDatabaseProductName());
		System.out.println("Database Product Version: "
				+ metadata.getDatabaseProductVersion());
		System.out.println("Logged User: " + metadata.getUserName());
		System.out.println("JDBC Driver: " + metadata.getDriverName());
		System.out.println("Driver Version: " + metadata.getDriverVersion());
		System.out.println("\n");
	}

	/**
	 *
	 * @return Arraylist with the table's name
	 * @throws SQLException
	 */
	public static ArrayList getTablesMetadata() throws SQLException {
		String table[] = { "TABLE" };
		ResultSet rs = null;
		ArrayList<String> tables = null;

		DateFormat dateFormat = new SimpleDateFormat("yyyy/MM/dd HH:mm:ss");
		System.out.println("BEGIN " + dateFormat.format(new Date()));
		// receive the Type of the object in a String array.
		rs = metadata.getTables(null, null, "%", table);
		System.out.println("END " + dateFormat.format(new Date())); //2016/11/16 12:08:43
		tables = new ArrayList<String>();
		while (rs.next()) {
			tables.add(rs.getString("TABLE_NAME"));
			System.out.println("Adding Table: " + rs.getString("TABLE_NAME"));
		}

		// results

// BEGIN 2019/10/21 07:48:50
// END 2019/10/21 07:58:15
// Adding Table: WWV_FLOW_DUAL100
// Adding Table: WWV_FLOW_LOV_TEMP
// Adding Table: WWV_FLOW_TEMP_TABLE
// Adding Table: DR$NUMBER_SEQUENCE
// Adding Table: DR$OBJECT_ATTRIBUTE
// Adding Table: DR$POLICY_TAB
// Adding Table: DR$THS
// Adding Table: DR$THS_PHRASE
// Adding Table: NTV2_XML_DATA
// Adding Table: OGIS_GEOMETRY_COLUMNS
// Adding Table: OGIS_SPATIAL_REFERENCE_SYSTEMS
// Adding Table: SDO_COORD_AXES
// Adding Table: SDO_COORD_AXIS_NAMES
// Adding Table: SDO_COORD_OPS
// Adding Table: SDO_COORD_OP_METHODS
// Adding Table: SDO_COORD_OP_PARAMS
// Adding Table: SDO_COORD_OP_PARAM_USE
// Adding Table: SDO_COORD_OP_PARAM_VALS
// Adding Table: SDO_COORD_OP_PATHS
// Adding Table: SDO_COORD_REF_SYS
// Adding Table: SDO_COORD_SYS
// Adding Table: SDO_CRS_GEOGRAPHIC_PLUS_HEIGHT
// Adding Table: SDO_CS_CONTEXT_INFORMATION
// Adding Table: SDO_CS_SRS
// Adding Table: SDO_DATUMS
// Adding Table: SDO_DATUMS_OLD_SNAPSHOT
// Adding Table: SDO_ELLIPSOIDS
// Adding Table: SDO_ELLIPSOIDS_OLD_SNAPSHOT
// Adding Table: SDO_PREFERRED_OPS_SYSTEM
// Adding Table: SDO_PREFERRED_OPS_USER
// Adding Table: SDO_PRIME_MERIDIANS
// Adding Table: SDO_PROJECTIONS_OLD_SNAPSHOT
// Adding Table: SDO_ST_TOLERANCE
// Adding Table: SDO_TOPO_DATA$
// Adding Table: SDO_TOPO_RELATION_DATA
// Adding Table: SDO_TOPO_TRANSACT_DATA
// Adding Table: SDO_TXN_IDX_DELETES
// Adding Table: SDO_TXN_IDX_EXP_UPD_RGN
// Adding Table: SDO_TXN_IDX_INSERTS
// Adding Table: SDO_UNITS_OF_MEASURE
// Adding Table: SDO_XML_SCHEMAS
// Adding Table: SRSNAMESPACE_TABLE
// Adding Table: MYTABLE
// Adding Table: AUDIT_ACTIONS
// Adding Table: DUAL
// Adding Table: HS$_PARALLEL_METADATA
// Adding Table: HS_BULKLOAD_VIEW_OBJ
// Adding Table: HS_PARTITION_COL_NAME
// Adding Table: HS_PARTITION_COL_TYPE
// Adding Table: IMPDP_STATS
// Adding Table: KU$NOEXP_TAB
// Adding Table: KU$_DATAPUMP_MASTER_10_1
// Adding Table: KU$_DATAPUMP_MASTER_11_1
// Adding Table: KU$_DATAPUMP_MASTER_11_1_0_7
// Adding Table: KU$_DATAPUMP_MASTER_11_2
// Adding Table: KU$_LIST_FILTER_TEMP
// Adding Table: KU$_LIST_FILTER_TEMP_2
// Adding Table: ODCI_PMO_ROWIDS$
// Adding Table: ODCI_SECOBJ$
// Adding Table: ODCI_WARNINGS$
// Adding Table: PLAN_TABLE$
// Adding Table: PSTUBTBL
// Adding Table: STMT_AUDIT_OPTION_MAP
// Adding Table: SYSTEM_PRIVILEGE_MAP
// Adding Table: TABLE_PRIVILEGE_MAP
// Adding Table: WRI$_ADV_ASA_RECO_DATA
// Adding Table: WRR$_REPLAY_CALL_FILTER
// Adding Table: HELP
// Adding Table: OL$
// Adding Table: OL$HINTS
// Adding Table: OL$NODES
// Adding Table: XDB$ACL
// Adding Table: XDB$ALL_MODEL
// Adding Table: XDB$ANY
// Adding Table: XDB$ANYATTR
// Adding Table: XDB$ATTRGROUP_DEF
// Adding Table: XDB$ATTRGROUP_REF
// Adding Table: XDB$ATTRIBUTE
// Adding Table: XDB$CHOICE_MODEL
// Adding Table: XDB$COMPLEX_TYPE
// Adding Table: XDB$ELEMENT
// Adding Table: XDB$GROUP_DEF
// Adding Table: XDB$GROUP_REF
// Adding Table: XDB$RESCONFIG
// Adding Table: XDB$SCHEMA
// Adding Table: XDB$SEQUENCE_MODEL
// Adding Table: XDB$SIMPLE_TYPE
// Adding Table: XDB$XIDX_IMP_T
		return tables;
	}

	/**
	 * Prints in the console the columns metadata, based in the Arraylist of
	 * tables passed as parameter.
	 *
	 * @param tables
	 * @throws SQLException
	 */
	public static void getColumnsMetadata(ArrayList<String> tables)
			throws SQLException {
		ResultSet rs = null;
		// Print the columns properties of the actual table
		for (String actualTable : tables) {
			rs = metadata.getColumns(null, null, actualTable, null);
			System.out.println(actualTable.toUpperCase());
			while (rs.next()) {
				System.out.println(rs.getString("COLUMN_NAME") + " "
						+ rs.getString("TYPE_NAME") + " "
						+ rs.getString("COLUMN_SIZE"));
			}
			System.out.println("\n");
		}

	}

	/**
	 *
	 * @param args
	 */
	public static void main(String[] args) {
		try {
			printGeneralMetadata();
			// Print all the tables of the database scheme, with their names and
			// structure
			getColumnsMetadata(getTablesMetadata());
		} catch (SQLException e) {
			System.err
					.println("There was an error retrieving the metadata properties: "
							+ e.getMessage());
		}
	}
}
